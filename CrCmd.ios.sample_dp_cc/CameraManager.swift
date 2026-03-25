import Foundation
import ImageCaptureCore
import CoreGraphics

final class CameraManager: NSObject {


    var paramTable: [Param] = []

    var onCameraNameChanged: ((String) -> Void)?
    var onStatusChanged: ((String) -> Void)?
    var onLog: ((String) -> Void)?
    var onDpUpdated: (() -> Void)?

    private let browser = ICDeviceBrowser()
    private var camera: ICCameraDevice?

    private(set) var isSessionOpen: Bool = false
    private var nextTransactionID: UInt32 = 1

    private var pendingOpenSessionCompletion: ((Bool) -> Void)?

    var hasCamera: Bool {
        camera != nil
    }

    override init() {
        super.init()
        browser.delegate = self
        browser.browsedDeviceTypeMask = ICDeviceTypeMask.camera
        updateStatus("idle")
        startBrowsing() // ★
    }

    func startBrowsing() {
        log("startBrowsing()")
        updateStatus("browsing")
        browser.start()
    }

    func stopBrowsing() {
        log("stopBrowsing()")
        browser.stop()
        updateStatus("browse stopped")
    }

    func openSession() {
        openSession(completion: nil)
    }

    func openSession(completion: ((Bool) -> Void)?) {
        guard let camera else {
            log("openSession(): no camera")
            completion?(false)
            return
        }

        if isSessionOpen {
            log("openSession(): already open")
            completion?(true)
            return
        }

        pendingOpenSessionCompletion = completion

        camera.delegate = self
        log("requestOpenSession() -> \(camera.name ?? "unknown")")
        updateStatus("opening session")
        camera.requestOpenSession()
    }

    func closeSession() {
        guard let camera else {
            log("closeSession(): no camera")
            return
        }
        log("requestCloseSession() -> \(camera.name ?? "unknown")")
        camera.requestCloseSession()
    }

    func sendCommand(opCode: PTP_OC, params: [UInt32], outData: Data?) {
        sendCommand(opCode: opCode, params: params, outData: outData, completion: nil)
    }

    func sendCommand(opCode: PTP_OC, params: [UInt32], outData: Data?,
                     completion: ((Bool, Data?) -> Void)?)
    {
        guard let camera else {
            log("sendCommand(): no camera")
            completion?(false, nil)
            return
        }
        guard isSessionOpen else {
            log("sendCommand(): session is not open")
            completion?(false, nil)
            return
        }

        let command = PTPCommandBuilder.makeCommand(
            opCode: opCode.rawValue,
            transactionID: 0,
            params: params
        )

        //log("SEND CMD opcode=0x\(hex16(opCode.rawValue)) params=[\(params.map { "0x" + hex32($0) }.joined(separator: ", "))]")

        //if let outData { log("SEND OUTDATA RAW \(outData.hexDump())") }

        // obj-c  didSendPTPCommand:inData:response:error:contextInfo:
        camera.requestSendPTPCommand(command, outData: outData) { [weak self] inData, response, error in
            guard let self else { return }

            if let error {
                self.log("PTP ERROR: \(error.localizedDescription)")
                completion?(false, nil)
                return
            }

            //self.log("RECV RESPONSE RAW \(response.hexDump())")
            //self.log("RECV INDATA RAW \(inData.hexDump())")

            do {
                /*let parsed*/_ = try PTPParser.parseContainer(response)
                //self.log("RECV PASS code=0x\(self.hex16(parsed.code)) params=[\(parsed.params.map { "0x" + self.hex32($0) }.joined(separator: ", "))]")

                // 必要ならここで parsed.code == 0x2001 を成功判定にしてもよい
                completion?(true, inData)
            } catch {
                self.log("RECV PARSE ERROR: \(error)")
                completion?(false, nil)
            }
        }
    }

    func connectSequence() {
        log("connectSequence(): begin")

        openSession() { [weak self] result in
            guard let self else { return }
            guard result else {
                self.log("connectSequence(): aborted at openSession")
                return
            }

            self.sendCommand(opCode: PTP_OC.OpenSession, params: [1], outData: nil) { [weak self] result, inData in
                guard let self else { return }
                guard result else { return }

                self.sendCommand(opCode: PTP_OC.SDIO_Connect, params: [1,0,0], outData: nil) { [weak self] result, inData in
                    guard let self else { return }
                    guard result else { return }

                    self.sendCommand(opCode: PTP_OC.SDIO_Connect, params: [2,0,0], outData: nil) { [weak self] result, inData in
                        guard let self else { return }
                        guard result else { return }

                        self.sendCommand(opCode: PTP_OC.SDIO_GetExtDeviceInfo, params: [0x012c], outData: nil) { [weak self] result, inData in
                            guard let self else { return }
                            guard result else { return }

                            self.sendCommand(opCode: PTP_OC.SDIO_Connect, params: [3,0,0], outData: nil) { [weak self] result, inData in
                                guard let self else { return }
                                guard result else { return }
                            }
                        }
                    }
                }
            }
        }
    }

    func getAllDP() {

        self.sendCommand(opCode: PTP_OC.SDIO_GetAllExtDevicePropInfo, params: [1/*onlyDiff*/], outData: nil) { [weak self] result, inData in
            guard let self else { return }
            guard result else { return }

            guard let inData else { return }

            //self.log("\(inData.hexDump())")

            let recvSize = inData.count
            let propNum = PTPParser.readUInt32LE(inData, offset: 0)
            _ = propNum

            var dp = 8

            while dp < recvSize {
                
                let pcode = PTPParser.readUInt16LE(inData, offset: dp)
                dp += 2

                let datatype = PTP_DT(rawValue: PTPParser.readUInt16LE(inData, offset: dp)) ?? .UNDEF
                dp += 2

                guard dp < recvSize else { break }
                let getset = inData[dp]
                dp += 1

                guard dp < recvSize else { break }
                let isenabled = inData[dp]
                dp += 1

                let factory = getVariableVal(datatype, inData, &dp)
                _ = factory

                let current = getVariableVal(datatype, inData, &dp)

                guard dp < recvSize else { break }
                let formflag = inData[dp]
                dp += 1

                var index = paramTable.count

                let dp_enum = DPC(rawValue: pcode) ?? .UNDEF

                if dp_enum != DPC.UNDEF {
                    var updated: Bool = false

                    for i in 0..<paramTable.count {
                        if paramTable[i].pcode == pcode {
                            index = i
                            break
                        }
                    }

                    if index == paramTable.count {
                        let newParam = Param(pcode: pcode)
                        paramTable.append(newParam)
                        updated = true
                    } else if paramTable[index].current != current {
                        updated = true
                    }

                    if updated {
                        log(String(
                                format: "  %04X:%@=%d", Int(pcode), String(describing: dp_enum), Int(current)
                        ))
                    }

                    paramTable[index].datatype = datatype
                    paramTable[index].getset = getset
                    paramTable[index].isenabled = isenabled
                    paramTable[index].current = current
                    paramTable[index].formflag = formflag
                    paramTable[index].currentIndex = 0
                    paramTable[index].enumNum = 0
                    paramTable[index].enums.removeAll()
                }

                switch formflag {
                case 0:
                    break

                case 1:
                    _ = getVariableVal(datatype, inData, &dp)
                    _ = getVariableVal(datatype, inData, &dp)
                    _ = getVariableVal(datatype, inData, &dp)

                case 2:
                    var num = PTPParser.readUInt16LE(inData, offset: dp)
                    dp += 2

                    for _ in 0..<num {
                        _ = getVariableVal(datatype, inData, &dp)
                    }

                    num = PTPParser.readUInt16LE(inData, offset: dp)
                    dp += 2

                    if dp_enum != DPC.UNDEF {
                        paramTable[index].enumNum = Int(num)
                        paramTable[index].enums = Array(repeating: 0, count: Int(num))
                    }

                    for i in 0..<Int(num) {
                        let data = getVariableVal(datatype, inData, &dp)
                        if dp_enum != DPC.UNDEF {
                            paramTable[index].enums[i] = data
                            if data == current {
                                paramTable[index].currentIndex = i
                            }
                        }
                    }

                default:
                    log("Control Transfer Timeout")
                }
            /*
                if updated {
                    log(String(
                            format: "%04x:%@, %d,%d,%d,%d, %ld,%ld",
                            Int(pcode),
                            String(describing: dp_enum),
                            Int(datatype),
                            Int(getset),
                            Int(isenabled),
                            Int(formflag),
                            paramTable[index].currentIndex,
                            Int(current)
                        )
                    )
                }
            */
            }
        }
        onDpUpdated?()
    }

    func getDP(_ dpCode: UInt16) -> Param? {
        for i in 0..<paramTable.count {
            if paramTable[i].pcode == dpCode {
                return paramTable[i]
            }
        }
        return nil
    }

    func setDP(_ dpCode: UInt16, _ dpVal: Int64) {
        for i in 0..<paramTable.count {
            if paramTable[i].pcode == dpCode {
            	if paramTable[i].isenabled != 1 { return }

				var outdata: Data
			    switch paramTable[i].datatype {
			    case .INT8, .UINT8:
			        let v = UInt8(truncatingIfNeeded: dpVal)
			        outdata = Data([v])

			    case .INT16, .UINT16:
			        let v = UInt16(truncatingIfNeeded: dpVal).littleEndian
			        outdata = withUnsafeBytes(of: v) { Data($0) }

			    case .INT32, .UINT32:
			        let v = UInt32(truncatingIfNeeded: dpVal).littleEndian
			        outdata = withUnsafeBytes(of: v) { Data($0) }

			    case .INT64, .UINT64:
			        let v = UInt64(truncatingIfNeeded: dpVal).littleEndian
			        outdata = withUnsafeBytes(of: v) { Data($0) }

				default:
					return
			    }
	            sendCommand(opCode: PTP_OC.SDIO_SetExtDevicePropValue, params: [UInt32(dpCode)], outData: outdata) { result, inData in
	                guard result else { return }
	        	}
            }
        }
        return
    }

    private func getVariableVal(_ datatype: PTP_DT, _ data: Data, _ dp: inout Int) -> Int64 {
        var val: Int64 = 0

        switch datatype {
        case .INT8:
            if dp < data.count {
                val = Int64(Int8(bitPattern: data[dp]))
                dp += 1
            }

        case .UINT8:
            if dp < data.count {
                val = Int64(data[dp])
                dp += 1
            }

        case .INT16:
            if dp + 1 < data.count {
                val = Int64(Int16(bitPattern: PTPParser.readUInt16LE(data, offset: dp)))
                dp += 2
            }

        case .UINT16:
            if dp + 1 < data.count {
                val = Int64(PTPParser.readUInt16LE(data, offset: dp))
                dp += 2
            }

        case .INT32:
            if dp + 3 < data.count {
                val = Int64(Int32(bitPattern: PTPParser.readUInt32LE(data, offset: dp)))
                dp += 4
            }

        case .UINT32:
            if dp + 3 < data.count {
                val = Int64(PTPParser.readUInt32LE(data, offset: dp))
                dp += 4
            }

        case .INT64:
            if dp + 7 < data.count {
                let u64 = PTPParser.readUInt64LE(data, offset: dp)
                val = Int64(bitPattern: u64)
                dp += 8
            }

        case .UINT64:
            if dp + 7 < data.count {
                let u64 = PTPParser.readUInt64LE(data, offset: dp)
                val = Int64(bitPattern: u64)
                dp += 8
            }

        case .STR:
            if dp < data.count {
                let strLen = Int(data[dp])
                dp += 1
                dp += strLen * 2
            }

        default:
            log("unknown datatype")
        }

        return val
    }

    private func updateStatus(_ text: String) {
        onStatusChanged?(text)
    }

    private func updateCameraName(_ text: String) {
        onCameraNameChanged?(text)
    }

    fileprivate func log(_ text: String) {
        onLog?(text)
    }

    fileprivate func hex16(_ value: UInt16) -> String {
        String(format: "%04X", value)
    }

    fileprivate func hex32(_ value: UInt32) -> String {
        String(format: "%08X", value)
    }
}

extension CameraManager: ICDeviceBrowserDelegate {

    func deviceBrowser(_ browser: ICDeviceBrowser,
                       didAdd device: ICDevice,
                       moreComing: Bool) {
        log("didAdd device: \(device.name ?? "unknown")")

        guard let cam = device as? ICCameraDevice else {
            log("device is not ICCameraDevice")
            return
        }

        camera = cam
        cam.delegate = self

        updateCameraName(cam.name ?? "unknown")
        updateStatus("camera found")

        log("camera assigned: \(cam.name ?? "unknown")")

        // 1台見つかったら、必要に応じてここで自動 open してもよい
        if !moreComing {
            log("device enumeration completed")
        }
    }

    func deviceBrowser(_ browser: ICDeviceBrowser,
                       didRemove device: ICDevice,
                       moreGoing: Bool) {
        log("didRemove device: \(device.name ?? "unknown")")

        if let cam = device as? ICCameraDevice, cam == camera {
            camera = nil
            isSessionOpen = false
            updateCameraName("")
            updateStatus("camera removed")
        }
    }
}

extension CameraManager: ICDeviceDelegate, ICCameraDeviceDelegate {

    // ICDeviceDelegate

    func device(_ device: ICDevice, didOpenSessionWithError error: (any Error)?) {
        if let error {
            log("didOpenSessionWithError: \(error.localizedDescription)")
            isSessionOpen = false
            updateStatus("open failed")

            pendingOpenSessionCompletion?(false)
            pendingOpenSessionCompletion = nil
            return
        }

        isSessionOpen = true
        log("session opened: \(device.name ?? "unknown")")
        updateStatus("session open")

        pendingOpenSessionCompletion?(true)
        pendingOpenSessionCompletion = nil
    }

    func device(_ device: ICDevice, didCloseSessionWithError error: (any Error)?) {
        if let error {
            log("didCloseSessionWithError: \(error.localizedDescription)")
        } else {
            log("session closed")
        }

        isSessionOpen = false
        updateStatus("session closed")
    }

    func device(_ device: ICDevice, didEncounterError error: (any Error)?) {
        if let error {
            log("device error: \(error.localizedDescription)")
            updateStatus("device error")
        }
    }

    func didRemove(_ device: ICDevice) {
        //
    }

    func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        log("cameraDeviceDidRemoveAccessRestriction")
    }

    func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        log("cameraDeviceDidEnableAccessRestriction")
    }

    func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        //
    }


    // ICCameraDeviceDelegate

    func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        log("cameraDevice didAdd items: \(items.count)")
    }

    func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {
        log("cameraDevice didRemove items: \(items.count)")
    }

    func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {
        log("cameraDevice didRenameItems: \(items.count)")
    }

    func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {
        log("cameraDeviceDidChangeCapability")
    }

    func cameraDevice(_ camera: ICCameraDevice,
                      didReceiveThumbnail thumbnail: CGImage?,
                      for item: ICCameraItem,
                      error: (any Error)?) {
        if let error {
            log("didReceiveThumbnail error: \(error.localizedDescription)")
        } else {
            log("didReceiveThumbnail for item: \(item.name ?? "unknown")")
        }
    }

    func cameraDevice(_ camera: ICCameraDevice,
                      didReceiveMetadata metadata: [AnyHashable : Any]?,
                      for item: ICCameraItem,
                      error: (any Error)?) {
        if let error {
            log("didReceiveMetadata error: \(error.localizedDescription)")
        } else {
            log("didReceiveMetadata for item: \(item.name ?? "unknown")")
        }
    }

    func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {
        //log("PTP EVENT RAW \(eventData.hexDump())")

        do {
            let parsed = try PTPParser.parseContainer(eventData)
            guard let event_enum = PTP_SDIE(rawValue: parsed.code) else { return }
            //log("PTP EVENT PARSED type=0x\(hex16(parsed.type)) code=0x\(hex16(parsed.code)) txid=\(parsed.transactionID) params=[\(parsed.params.map { "0x" + hex32($0) }.joined(separator: ", "))]")
            log("e-\(hex16(parsed.code)):\(String(describing: event_enum)) [\(parsed.params.map {String($0)}.joined(separator: ","))]")
            if parsed.code == PTP_SDIE.DevicePropChanged.rawValue {
                getAllDP()
            }
        } catch {
            log("PTP EVENT PARSE ERROR: \(error)")
        }
    }
}
