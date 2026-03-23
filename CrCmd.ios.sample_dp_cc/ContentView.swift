import SwiftUI

struct ContentView: View {
    @StateObject private var vm = CameraViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            GroupBox("Camera") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Status:")
                            .font(.headline)
                        Text(vm.cameraStatusText)
                    }

                    HStack {
                        Text("Device:")
                            .font(.headline)
                        Text(vm.cameraName.isEmpty ? "(none)" : vm.cameraName)
                    }

                    HStack(spacing: 12) {
                    /*
                        Button("Start Browse") {
                            vm.startBrowse()
                        }

                        Button("Stop Browse") {
                            vm.stopBrowse()
                        }

                        Button("Open Session") {
                            vm.openSession()
                        }
                        .disabled(!vm.hasCamera)
                    */
                        Button("connect") {
                            vm.connect()
                        }
                        .disabled(!vm.hasCamera)
                    }
                    /*
                    HStack(spacing: 12) {
                        Button("Close Session") {
                            vm.closeSession()
                        }
                        .disabled(!vm.hasCamera)

                        Button("get all DP") {
                            vm.getAllDP()
                        }
                        .disabled(!vm.hasCamera)
                    }
                    */
                }.frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("PTP Commands") {
                VStack(alignment: .leading, spacing: 12) {
					/*
                    HStack(spacing: 12) {
	                    Button("Send 0x1001") {
	                        //
	                    }
	                    .disabled(!vm.canSendCommand)

                        Button("Send 0x9201") {
                            //
                        }
                        .disabled(!vm.canSendCommand)

                        Button("Send 0x9202") {
                            //
                        }
                        .disabled(!vm.canSendCommand)
                    }

                    Divider()

                    Text("Custom Command")
                        .font(.headline)
					*/

                    Button("infoDP") {
                        vm.infodp()
                        //vm.sendCustomCommand()
                    }
                    .disabled(!vm.canSendCommand)

                    HStack {
                        Text("DP")
                        TextField("0000", text: $vm.dpCodeHex)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.allCharacters)
                    }

                    HStack {
                        Text("Params")
                        TextField("00000001,00000002", text: $vm.dpParams)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.allCharacters)
                    }

                }
            }

            GroupBox("Log") {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(vm.logText)
                                .font(.system(.footnote, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .topLeading)

                            Color.clear
                                .frame(height: 1)
                                .id("BOTTOM")
                        }
                    }
                    .onChange(of: vm.logText) {
                        withAnimation {
                            proxy.scrollTo("BOTTOM", anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

#Preview {
    ContentView()
}