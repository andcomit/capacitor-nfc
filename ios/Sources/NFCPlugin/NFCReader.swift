import CoreNFC
import Foundation

@objc public class NFCReader: NSObject, NFCTagReaderSessionDelegate {
  private var readerSession: NFCTagReaderSession?
  public var onUIDReceived: ((String, String) -> Void)?
  public var onError: ((Error) -> Void)?

  @objc public func startScanning() {
    print("🛰️ NFCReader startScanning called")

    guard NFCTagReaderSession.readingAvailable else {
      print("❌ NFC scanning not supported on this device")
      return
    }

    // Polling ottimizzato per UID — evita .iso18092 per massima compatibilità SE2
    readerSession = NFCTagReaderSession(
      pollingOption: [.iso14443, .iso15693],
      delegate: self,
      queue: nil
    )
    readerSession?.alertMessage = "Avvicina la parte superiore dell’iPhone al tag NFC."
    readerSession?.begin()
  }

  @objc public func cancelScanning() {
    readerSession?.invalidate()
    readerSession = nil
  }

  public func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
    print("✅ NFC session active")
  }

  public func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error)
  {
    print("❌ NFC session invalidated: \(error.localizedDescription)")
    onError?(error)
    readerSession = nil
  }

  public func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
    guard let tag = tags.first else { return }

    if tags.count > 1 {
      session.alertMessage = "Più di un tag rilevato. Rimuovi gli altri e riprova."
      DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
        session.restartPolling()
      }
      return
    }

    session.connect(to: tag) { error in
      if let error = error {
        print("❌ Errore connessione: \(error.localizedDescription)")
        session.invalidate(errorMessage: "Impossibile connettersi al tag.")
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

      print("📲 UID: \(uidHex) [\(tagType)]")

      session.alertMessage =
        uidHex.isEmpty
        ? "Tag rilevato (UID non disponibile)."
        : "Tag rilevato. UID: \(uidHex)"

      session.invalidate()
      self.onUIDReceived?(uidHex, tagType)
    }
  }
}
