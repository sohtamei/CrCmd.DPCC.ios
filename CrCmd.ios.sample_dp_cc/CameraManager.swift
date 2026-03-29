import Foundation
import ImageCaptureCore
import CoreGraphics

final class CameraManager: NSObject {

    var dpParams: [Param] = []

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
                                _ = self
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
                let formflag = Formflag(rawValue: Int(inData[dp])) ?? .None
                dp += 1

                var index = dpParams.count

                let dp_enum = DPC(rawValue: pcode) ?? .UNDEF

                if dp_enum != DPC.UNDEF {
                    var updated: Bool = false

                    for i in 0..<dpParams.count {
                        if dpParams[i].pcode == pcode {
                            index = i
                            break
                        }
                    }

                    if index == dpParams.count {
                        let newParam = Param(pcode: pcode)
                        dpParams.append(newParam)
                        updated = true
                    } else if dpParams[index].current != current {
                        updated = true
                    }

                    if updated {
                        log(String(
                                format: "  %04X:%@=%d", Int(pcode), String(describing: dp_enum), Int(current)
                        ))
                    }

                	dpParams[index].modeRW = .Invalid
                    switch isenabled {		// 0-invalid, 1-R/W, 2-R
                    case 0:
						break
					case 1:
	                    switch getset {		// 0-R, 1-R/W
	                    case 0:
	                    	dpParams[index].modeRW = .R
	                    case 1:
	                    	dpParams[index].modeRW = .RW
						default:
							break
						}
                    case 2:
                    	dpParams[index].modeRW = .R
					default:
						break
					}


                    dpParams[index].datatype = datatype
                    dpParams[index].current = current
                    dpParams[index].formflag = formflag
                    dpParams[index].currentIndex = 0
                    dpParams[index].enums.removeAll()
                }

                switch formflag {
                case .None:
                    break

                case .Range:
                    if dp_enum != DPC.UNDEF {
                        dpParams[index].enums = Array(repeating: 0, count: 3)
                    }
                    for i in 0..<3 {
                        let data = getVariableVal(datatype, inData, &dp)
                        if dp_enum != DPC.UNDEF {
                            dpParams[index].enums[i] = data
                        }
                    }

                case .Enum:
                    var num = PTPParser.readUInt16LE(inData, offset: dp)
                    dp += 2

                    for _ in 0..<num {
                        _ = getVariableVal(datatype, inData, &dp)
                    }

                    num = PTPParser.readUInt16LE(inData, offset: dp)
                    dp += 2

                    if dp_enum != DPC.UNDEF {
                        dpParams[index].enums = Array(repeating: 0, count: Int(num))
                    }

                    for i in 0..<Int(num) {
                        let data = getVariableVal(datatype, inData, &dp)
                        if dp_enum != DPC.UNDEF {
                            dpParams[index].enums[i] = data
                            if data == current {
                                dpParams[index].currentIndex = i
                            }
                        }
                    }
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
                            dpParams[index].currentIndex,
                            Int(current)
                        )
                    )
                }
            */
            }
	        onDpUpdated?()
        }
    }

    func getDPCC(_ pcode: UInt16) -> Param? {
        for i in 0..<dpParams.count {
            if dpParams[i].pcode == pcode {
                return dpParams[i]
            }
        }

        for i in 0..<ccParams.count {
            if ccParams[i].pcode == pcode {
                return ccParams[i]
            }
        }
        return nil
    }

    func setDPCC(_ pcode: UInt16, _ val: Int64) {
		guard let param = getDPCC(pcode) else { return }

		var outdata: Data
	    switch param.datatype {
	    case .INT8, .UINT8:
	        let v = UInt8(truncatingIfNeeded: val)
	        outdata = Data([v])

	    case .INT16, .UINT16:
	        let v = UInt16(truncatingIfNeeded: val).littleEndian
	        outdata = withUnsafeBytes(of: v) { Data($0) }

	    case .INT32, .UINT32:
	        let v = UInt32(truncatingIfNeeded: val).littleEndian
	        outdata = withUnsafeBytes(of: v) { Data($0) }

	    case .INT64, .UINT64:
	        let v = UInt64(truncatingIfNeeded: val).littleEndian
	        outdata = withUnsafeBytes(of: v) { Data($0) }

		default:
			return
	    }

		if !param.cc_dp {
        	if param.modeRW != .RW { return }
            sendCommand(opCode: PTP_OC.SDIO_SetExtDevicePropValue, params: [UInt32(pcode),1], outData: outdata) { result, inData in
                guard result else { return }
        	}
		} else {
            sendCommand(opCode: PTP_OC.SDIO_ControlDevice, params: [UInt32(pcode),1], outData: outdata) { result, inData in
                guard result else { return }
        	}
		}
        return
    }

    func setDP(_ pcode: UInt16, _ type: TypeIncDec) {
		guard let param = getDPCC(pcode) else { return }
		if param.cc_dp { return }

		var val: Int64
		switch param.formflag {
		case .Range:
			if param.enums.count != 3 { return }

			val = param.current
			switch type {
			case .Inc:
				if val >= param.enums[1] { return }
				val += param.enums[2]
			case .Dec:
				if val <= param.enums[0] { return }
				val -= param.enums[2]
			case .Max:
				val = param.enums[1]
			case .Min:
				val = param.enums[0]
			}

		case .Enum:
			var index = param.currentIndex
			switch type {
			case .Inc:
				if index >= param.enums.count-1 { return }
				index += 1
			case .Dec:
				if index <= 0 { return }
				index -= 1
			case .Max:
				index = param.enums.count-1
			case .Min:
				index = 0
			}
			val = param.enums[index]

		default:
			return
		}
		setDPCC(pcode, val)
	}

    func setCC(_ pcode: UInt16, _ val: Int64) {
		setDPCC(pcode, val)
	}

	func liveview(completion: ((Bool, Data?) -> Void)?) {
        self.sendCommand(opCode: PTP_OC.GetObject, params: [0xFFFFC002], outData: nil) { result, inData in		// liveview
            guard result else {
            	completion?(false, nil)
                return
            }
            guard let inData else {
            	completion?(false, nil)
                return
            }
			let lv_offset   = Int(PTPParser.readUInt32LE(inData, offset: 0))
			let lv_size     = Int(PTPParser.readUInt32LE(inData, offset: 4))
			//let prop_offset = Int(PTPParser.readUInt32LE(inData, offset: 8))
			//let prop_size   = Int(PTPParser.readUInt32LE(inData, offset: 12))
			if lv_offset+lv_size > inData.count {
            	completion?(false, nil)
                return
            }

            let lvData = inData.subdata(in: lv_offset ..< (lv_offset+lv_size))
            completion?(true, lvData)
            return
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
