import Foundation
import Combine
import SwiftUI
import UIKit

final class CameraViewModel: ObservableObject {

	@Published var isConnected = false
	@Published var isLiveview = false

    @Published var cameraName: String = ""
    @Published var cameraStatusText: String = "idle"
    @Published var jpegData: Data = Data()

    @Published var codeHex: String = "5007"

    @Published var dpParams: String = ""
    @Published var modeInput: ModeInput = .Disabled
    @Published var dpSetVal: String = "0"

    @Published var logText: String = ""

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
            self?.updateDPCC()
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
		isConnected = true
    }

    func closeSession() {
        manager.closeSession()
    }

	func updateDPCC_work() -> String? {
        var text = ""

        guard let pcode = UInt16(codeHex, radix: 16) else { return nil }
        guard let param = manager.getDPCC(pcode) else { return nil }
		var _modeInput: ModeInput = .Disabled

        if param.cc_dp {
	        text = String(describing: param.formflag) + "="
                + param.enums.map {String($0)}.joined(separator: ",")
	    	_modeInput = .CC
		} else if param.datatype == PTP_DT.STR {
        	text = "mode=" + String(describing: param.modeRW)
        } else {
        	text = "current=" + String(param.current) + String(format: "(0x%X)\n", param.current)
        		+ "mode=" + String(describing: param.modeRW) + "\n"
        		+ String(describing: param.formflag) + "="
                + param.enums.map {String($0)}.joined(separator: ",")
			if param.modeRW == .RW { _modeInput = .DP }
        }
    	DispatchQueue.main.async { self.modeInput = _modeInput }
		return text
	}

    func updateDPCC() {
		guard let text = updateDPCC_work() else { return }
    	DispatchQueue.main.async { self.dpParams = text }
    }

    func setDPCC() {
        guard let pcode = UInt16(codeHex, radix: 16) else { return }

	    if dpSetVal.hasPrefix("0x") || dpSetVal.hasPrefix("0X") {
			guard let setVal = Int64(String(dpSetVal.dropFirst(2)), radix: 16) else {return}
		    manager.setDPCC(pcode, setVal)
	    } else {
			guard let setVal = Int64(dpSetVal) else {return}
		    manager.setDPCC(pcode, setVal)
	    }
    }

    func setDP(_ type: TypeIncDec) {
        guard let pcode = UInt16(codeHex, radix: 16) else { return }
	    manager.setDP(pcode, type)
    }

    func setCC(_ val: Int64) {
        guard let pcode = UInt16(codeHex, radix: 16) else { return }
	    manager.setCC(pcode, val)
    }

    func describingDPCC(_ codeStr: String) -> String {
		guard let pcode = UInt16(codeStr, radix: 16) else { return "(unknown)" }

		guard let dp_enum = DPC(rawValue: pcode) else {
			guard let cc_enum = PTP_CC(rawValue: pcode) else { return "(unknown)" }
			return String(describing: cc_enum)
		}
		return String(describing: dp_enum)
    }

    func liveview() {
		manager.liveview() { result, lvData in
			if result {
				guard let lvData else { return }
		    	DispatchQueue.main.async { self.jpegData = lvData }
			}
			return
		}
		isLiveview = true
    }

    private func appendLocalLog(_ message: String) {
        if logText.isEmpty {
            logText = message
        } else {
            logText += "\n" + message
        }
    }
}
