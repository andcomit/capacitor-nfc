import CoreNFC
import Foundation

@objc public class NFCReader: NSObject, NFCTagReaderSessionDelegate {
  private var readerSession: NFCTagReaderSession?
  public var onUIDReceived: ((String, String) -> Void)?  // (uidHex, type)
  public var onError: ((Error) -> Void)?

  @objc public func startScanning() {
    print("NFCReader startScanning called")
    guard NFCTagReaderSession.readingAvailable else {
      print("NFC scanning not supported on this device")
      return
    }
    // Polling options: include common ones
    readerSession = NFCTagReaderSession(
      pollingOption: [.iso14443, .iso15693, .iso18092], delegate: self, queue: nil)
    readerSession?.alertMessage = "Hold your iPhone near the NFC tag."
    readerSession?.begin()
  }

  @objc public func cancelScanning() {
    if let session = readerSession {
      session.invalidate()
    }
    readerSession = nil
  }

  public func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

  public func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error)
  {
    print("NFC reader session invalidated: \(error.localizedDescription)")
    self.onError?(error)
    readerSession = nil
  }

  public func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
    if tags.count > 1 {
      session.alertMessage = "More than one tag detected. Remove extras and try again."
      DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
        session.restartPolling()
      }
      return
    }

    let tag = tags.first!
    session.connect(to: tag) { (error: Error?) in
      if let error = error {
        session.invalidate(errorMessage: "Unable to connect to tag.")
        self.onError?(error)
        return
      }

      var uidHex = ""
      var tagType = "Unknown"

      switch tag {
      case .iso7816(let iso7816Tag):
        uidHex = iso7816Tag.identifier.map { String(format: "%02X", $0) }.joined()
        tagType = "ISO7816"
      case .miFare(let miFareTag):
        uidHex = miFareTag.identifier.map { String(format: "%02X", $0) }.joined()
        tagType = "MiFare"
      case .feliCa(let feliCaTag):
        uidHex = feliCaTag.currentIDm.map { String(format: "%02X", $0) }.joined()
        tagType = "FeliCa"
      case .iso15693(let iso15693Tag):
        uidHex = iso15693Tag.identifier.map { String(format: "%02X", $0) }.joined()
        tagType = "ISO15693"
      @unknown default:
        tagType = "Unknown"
      }

      // Return UID to caller
      if !uidHex.isEmpty {
        session.alertMessage = "UID: \(uidHex)"
        session.invalidate()
        self.onUIDReceived?(uidHex, tagType)
      } else {
        session.alertMessage = "Tag detected but UID not available."
        session.invalidate()
        self.onUIDReceived?("", tagType)
      }
    }
  }
}
