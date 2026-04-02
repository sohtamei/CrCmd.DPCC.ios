import Foundation
import Combine
import SwiftUI
import UIKit

final class CameraViewModel: ObservableObject {

    // 1st line
    @Published var cameraName: String = "(none)"
    @Published var cameraStatus: String = "idle"
    @Published var jpegData: Data = Data()

    // 2nd line
	@Published var isLiveview = false

    // 3rd line
    @Published var codeHex: String = "5007"

    // 4th line
    @Published var dpParams: String = ""

    // 5th line
    @Published var modeInput: ModeInput = .Disabled
    @Published var dpSetVal: String = "0"

    // 6th line
    @Published var logText: String = ""

    private let manager = CameraManager()
    private var lvTimer: Timer?

    init() {
        manager.onCameraNameChanged = { [weak self] name in
            DispatchQueue.main.async {
                self?.cameraName = name
            }
        }

        manager.onStatusChanged = { [weak self] status in
            DispatchQueue.main.async {
                self?.stopTimer()
                self?.cameraStatus = status
            }
        }

        manager.onLog = { [weak self] line in
            self?.outputLog(line)
        }

        manager.onDpUpdated = { [weak self] in
            self?.updateDPCC()
        }
    }

    func connect() {
        manager.connectSequence() { result in
			if result {
			    DispatchQueue.main.async {
	                self.cameraStatus = "connected"
	                self.outputLog("connected")
	                self.startTimer()
			    }
			} else {
				self.disconnect()
			}
        }
    }

    func disconnect() {
        manager.disconnectSequence() { result in
		    DispatchQueue.main.async {
                self.stopTimer()
                self.cameraStatus = "disconnected"
                self.outputLog("disconnected")
			}
        }
    }

    func startTimer() {
        lvTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            self?.targetFunc()
        }
    }

    func stopTimer() {
        lvTimer?.invalidate()
        lvTimer = nil
    }

    private func targetFunc() {
        if isLiveview {
			manager.liveview() { result, lvData in
				if result {
					guard let lvData else { return }
			    	DispatchQueue.main.async { self.jpegData = lvData }
				}
				return
			}
		}
    }

    func toggleLiveview() {
		isLiveview.toggle()
    }

	func updateDPCC_work() -> String? {
        guard let pcode = UInt16(codeHex, radix: 16) else { return nil }
        guard let param = manager.getDPCC(pcode) else { return nil }
		var _modeInput: ModeInput = .Disabled

        var text = ""
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
		    _ = manager.setDPCC(pcode, setVal)
	    } else {
			guard let setVal = Int64(dpSetVal) else {return}
		    _ = manager.setDPCC(pcode, setVal)
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

    func setCC(_ val1: Int64, _ val2: Int64) {
        guard let pcode = UInt16(codeHex, radix: 16) else { return }
	    manager.setCC(pcode, val1)
		DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) {
		    self.manager.setCC(pcode, val2)
		}
    }

    func describingDPCC(_ codeStr: String) -> String {
		guard let pcode = UInt16(codeStr, radix: 16) else { return "(unknown)" }

		guard let dp_enum = DPC(rawValue: pcode) else {
			guard let cc_enum = PTP_CC(rawValue: pcode) else { return "(unknown)" }
			return String(describing: cc_enum)
		}
		return String(describing: dp_enum)
    }

	func listcc() {
		manager.listcc()
	}

	func setupCamera() {
		manager.setupCamera(nil)
	}

    private func outputLog(_ line: String) {
		//guard let self = self else { return }
        DispatchQueue.main.async {
            if self.logText.isEmpty {
                self.logText = line
            } else {
                self.logText += "\n" + line
            }
            print(line)
        }
    }
}
