import Foundation
import Combine

final class CameraViewModel: ObservableObject {

    @Published var cameraName: String = ""
    @Published var cameraStatusText: String = "idle"
    @Published var logText: String = ""
    @Published var dpCodeHex: String = "5007"
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

    func sendCustomCommand() {
        let opcodeString = dpCodeHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let opCode = UInt16(opcodeString, radix: 16) else {
            appendLocalLog("ERROR: invalid opcode hex: \(dpCodeHex)")
            return
        }

        let params = parseParams(dpParams)
        //manager.sendCommand(opCode: opCode, params: params, outData: nil)
    }

    func getAllDP() {
        manager.getAllDP()
    }

    func infodp() {
/*
        guard let dpCode = UInt16(dpCodeHex.trimmingCharacters(in: .whitespacesAndNewlines), radix: 16) else {
            appendLocalLog("ERROR: invalid dpCode hex: \(dpCodeHex)")
            return
        }

        let dp_enum = DPC(rawValue: dpCode) ?? .UNDEF

        let dp_param = manager.getDP(dpCode)
    	if dp_param == nil { return }

        if dp_param.datatype == PTP_DT.STR.rawValue {
	        dpParams = String(describing: dp_enum) + "\n"
        } else {
	        dpParams = String(describing: dp_enum) + "\n"
	                 + String(format: "datatype=%d\n", dp_param.datatype)
        }
*/
    }

/*
        printf("  get enable=%d\n", devProp.IsGetEnableCurrentValue());
        printf("  set enable=%d\n", devProp.IsSetEnableCurrentValue());
        printf("  variable  =%d\n", devProp.GetPropertyVariableFlag());
        printf("  enable    =%d\n", devProp.GetPropertyEnableFlag());
        printf("  valueType =0x%x\n", dataType);
        if(dataType == SCRSDK::CrDataType_STR) {
            CrCout << "  current   =\"" << _getCurrentStr(&devProp) << "\"\n";
        } else {
            printf("  current   =0x%" PRIx64 "(%" PRId64 ")\n", devProp.GetCurrentValue(), devProp.GetCurrentValue());

            std::vector<int64_t> possible = _getPossible(devProp.GetValueType(), devProp.GetValues(), devProp.GetValueSize());
            printf("  possible  =");
            for(int i = 0; i < possible.size(); i++) {
                printf("0x%" PRIx64 "(%" PRId64 "),", possible[i], possible[i]);
            }
            printf("\n");

        var pcode: UInt16 = 0
        var datatype: UInt16 = 0
        var getset: UInt8 = 0        // 0-R, 1-R/W
        var isenabled: UInt8 = 0     // 0-invalid, 1-R/W, 2-R
        var current: Int32 = 0
        var formflag: UInt8 = 0
        var enums: [Int32] = []
        var enumNum: Int = 0
*/
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