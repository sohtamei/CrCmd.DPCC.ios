import Foundation
import Combine

final class CameraViewModel: ObservableObject {

    @Published var cameraName: String = ""
    @Published var cameraStatusText: String = "idle"
    @Published var logText: String = ""
    @Published var dpCodeHex: String = "5007"
    @Published var dpSetVal: String = "0x00"
    @Published var dpParams: String = "xx"

    private let manager = CameraManager()

    var hasCamera: Bool {
        manager.hasCamera
    }

    var canSendCommand: Bool {
        manager.isSessionOpen
    }

    init() {
        manager.onCameraNameChanged = { [weak self] name in
            DispatchQueue.main.async {
                self?.cameraName = name
            }
        }

        manager.onStatusChanged = { [weak self] status in
            DispatchQueue.main.async {
                self?.cameraStatusText = status
            }
        }

        manager.onLog = { [weak self] line in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.logText.isEmpty {
                    self.logText = line
                } else {
                    self.logText += "\n" + line
                }
                print(line)
            }
        }

        manager.onDpUpdated = { [weak self] in
            self?.updatedp()
        }
    }

    func startBrowse() {
        manager.startBrowsing()
    }

    func stopBrowse() {
        manager.stopBrowsing()
    }

    func openSession() {
        manager.openSession()
    }

    func connect() {
        manager.connectSequence()
    }

    func closeSession() {
        manager.closeSession()
    }

    func updatedp() {
        guard let dpCode = UInt16(dpCodeHex, radix: 16) else { return }

        guard let dp_enum = DPC(rawValue: dpCode) else { return }

        guard let dp_param = manager.getDP(dpCode) else { return }

        var text = String(describing: dp_enum) + "\n"
                 + "datatype=" + String(describing: dp_param.datatype) + "\n"
        if dp_param.datatype == PTP_DT.STR {
        } else {
        	text += "current=" + String(dp_param.current) + "\n"
        			 +  "getset=" + String(dp_param.getset) + "\n"
        			 +  "isenabled=" + String(dp_param.isenabled) + "\n"
        			 +  "formflag=" + String(dp_param.formflag) + "\n"
                	 +  "enums=" + dp_param.enums.map {String($0)}.joined(separator: ",") //+ "\n"
        }
		//appendLocalLog(dpParams + "\n")

    	DispatchQueue.main.async {
			self.dpParams = text
		}
    }

    func setdp() {
        guard let dpCode = UInt16(dpCodeHex, radix: 16) else { return }

	    if dpSetVal.hasPrefix("0x") || dpSetVal.hasPrefix("0X") {
			guard let setVal = Int64(String(dpSetVal.dropFirst(2)), radix: 16) else {return}
		    manager.setDP(dpCode, setVal)
	    } else {
			guard let setVal = Int64(dpSetVal) else {return}
		    manager.setDP(dpCode, setVal)
	    }
    }

    private func parseParams(_ text: String) -> [UInt32] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return []
        }

        return trimmed
            .split(separator: ",")
            .compactMap { part in
                let s = part.trimmingCharacters(in: .whitespacesAndNewlines)
                return UInt32(s, radix: 16)
            }
    }

    private func appendLocalLog(_ message: String) {
        if logText.isEmpty {
            logText = message
        } else {
            logText += "\n" + message
        }
    }
}
