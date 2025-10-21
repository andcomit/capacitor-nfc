import CoreNFC
import Foundation

@objc public class NFCWriter: NSObject, NFCNDEFReaderSessionDelegate {
  private var writerSession: NFCNDEFReaderSession?
  private var messageToWrite: NFCNDEFMessage?

  public var onWriteSuccess: (() -> Void)?
  public var onError: ((Error) -> Void)?

  @objc public func startWriting(message: NFCNDEFMessage) {
    print("✍️ NFCWriter startWriting called")
    self.messageToWrite = message

    guard NFCNDEFReaderSession.readingAvailable else {
      print("❌ NFC writing not supported on this device")
      return
    }

    writerSession = NFCNDEFReaderSession(
      delegate: self,
      queue: nil,
      invalidateAfterFirstRead: false
    )

    writerSession?.alertMessage = "Avvicina la parte superiore dell’iPhone al tag NFC per scrivere."
    writerSession?.begin()
  }

  public func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
    print("NFC writer session active")
  }

  public func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
    onError?(error)
    writerSession = nil
  }

  // Non usata per scrittura ma deve essere implementata
  public func readerSession(
    _ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]
  ) {
    // no-op
  }

  public func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
    if tags.count > 1 {
      session.alertMessage = "Più di un tag rilevato. Rimuovi gli altri e riprova."
      DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
        session.restartPolling()
      }
      return
    }

    guard let tag = tags.first else { return }

    session.connect(to: tag) { error in
      if let error = error {
        session.invalidate(errorMessage: "Impossibile connettersi al tag.")
        self.onError?(error)
        return
      }

      tag.queryNDEFStatus { ndefStatus, capacity, error in
        if let error = error {
          session.invalidate(errorMessage: "Impossibile interrogare lo stato NDEF del tag.")
          self.onError?(error)
          return
        }

        switch ndefStatus {
        case .notSupported:
          session.invalidate(errorMessage: "Il tag non è compatibile con NDEF.")

        case .readOnly:
          session.invalidate(errorMessage: "Il tag è in sola lettura.")

        case .readWrite:
          guard let message = self.messageToWrite else {
            session.invalidate(errorMessage: "Nessun messaggio da scrivere.")
            return
          }

          tag.writeNDEF(message) { error in
            if let error = error {
              session.invalidate(errorMessage: "Scrittura del messaggio NDEF fallita.")
              self.onError?(error)
              return
            }

            session.alertMessage = "Messaggio NDEF scritto con successo."
            session.invalidate()
            self.onWriteSuccess?()
          }

        @unknown default:
          session.invalidate(errorMessage: "Stato NDEF sconosciuto.")
        }
      }
    }
  }
}
