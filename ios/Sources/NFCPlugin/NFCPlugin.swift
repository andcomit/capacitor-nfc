import Capacitor
import CoreNFC
import Foundation

@objc(NFCPlugin)
public class NFCPlugin: CAPPlugin, CAPBridgedPlugin {
  public let identifier = "NFCPlugin"
  public let jsName = "NFC"
  public let pluginMethods: [CAPPluginMethod] = [
    CAPPluginMethod(name: "isSupported", returnType: CAPPluginReturnPromise),
    CAPPluginMethod(name: "cancelWriteAndroid", returnType: CAPPluginReturnPromise),
    CAPPluginMethod(name: "startScan", returnType: CAPPluginReturnPromise),
    CAPPluginMethod(name: "cancelScan", returnType: CAPPluginReturnPromise),
    CAPPluginMethod(name: "writeNDEF", returnType: CAPPluginReturnPromise),
  ]

  private let reader = NFCReader()

  @objc func isSupported(_ call: CAPPluginCall) {
    call.resolve(["supported": NFCTagReaderSession.readingAvailable])
  }

  @objc func cancelWriteAndroid(_ call: CAPPluginCall) {
    call.reject("Function not implemented for iOS")
  }

  @objc func startScan(_ call: CAPPluginCall) {
    print("📡 startScan (UID only)")

    reader.onUIDReceived = { uid, type in
      let response: [String: Any] = [
        "uid": uid,
        "type": type,
      ]
      self.notifyListeners("nfcTag", data: response)
    }

    reader.onError = { error in
      if let nfcError = error as? NFCReaderError,
        nfcError.code != .readerSessionInvalidationErrorUserCanceled
      {
        self.notifyListeners("nfcError", data: ["error": nfcError.localizedDescription])
      }
    }

    reader.startScanning()
    call.resolve()
  }

  @objc func cancelScan(_ call: CAPPluginCall) {
    reader.cancelScanning()
    call.resolve()
  }

  @objc func writeNDEF(_ call: CAPPluginCall) {
    // Lasciato per compatibilità futura se vuoi aggiungere scrittura
    call.reject("Writing not supported in this UID-only implementation")
  }
}
