import SwiftUI

struct ContentView: View {
    @StateObject private var vm = CameraViewModel()
    @FocusState private var isTextFieldFocused: Bool

    let candidates = [
		"D20D (Shutter_Speed)",
		"5007 (F_Number)",
		"5010 (Exposure_Bias_Compensation)",
		"D21E (ISO_Sensitivity)",
		"500E (Exposure_Program_Mode)",
		"D2C1 (S1_Button)",
		"D2C2 (S2_Button)",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            GroupBox("Camera - DP,CC") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
				        VStack(alignment: .leading) {
		                    HStack {
								Button {
								    vm.connect()
								} label: {
								    Text("connect")
								        .foregroundColor(
								        	!vm.hasCamera ? .gray :
								        	vm.isConnected ? .white : .primary)
								        .frame(width: 80, height: 32)
								        .background(
								            Capsule()
								                .fill(vm.isConnected ? Color.blue : Color(.systemBackground))
								        )
								}.disabled(!vm.hasCamera)

		                        if vm.cameraName.isEmpty {
		                        	Text("(none)")
		                        } else {
			                        Text(vm.cameraName + " - " + vm.cameraStatusText)
		                        }
							}

		                    HStack {
		                        Button {
		                            vm.liveview()
								} label: {
								    Text("LiveView")
								        .foregroundColor(
								        	!vm.canSendCommand ? .gray :
								        	vm.isLiveview ? .white : .primary)
								        .frame(width: 80, height: 32)
								        .background(
								            Capsule()
								                .fill(vm.isLiveview ? Color.blue : Color(.systemBackground))
								        )
		                        }.disabled(!vm.canSendCommand)

		                        Button("listcc") {
		                            //vm.listcc()
		                        }
			                    .disabled(!vm.canSendCommand)
		                    }
						} // VStack
					    Spacer()

						if let uiImage = UIImage(data: vm.jpegData) {
						    Image(uiImage: uiImage)
						        .resizable()
						        .scaledToFit()
						        .frame(width: 160, height: 90)
						}
                    }

                    HStack(alignment: .top) {
                    	HStack {
	                        Text("code 0x")
				            TextField("0000", text: $vm.codeHex)
				                .textFieldStyle(.roundedBorder)
				                .focused($isTextFieldFocused)
				                .frame(width: 80)
					            .onSubmit {
			                    	vm.updateDPCC()
					            }
					            .onChange(of: isTextFieldFocused) { focused in
					                if !focused {
					                    if vm.canSendCommand {
					                    	vm.updateDPCC()
					                    }
					                }
					            }
				        	if !isTextFieldFocused {
				            	Text(vm.describingDPCC(vm.codeHex))
		            		}
						}

			            if isTextFieldFocused {
			                VStack(spacing: 0) {
			                    ForEach(candidates, id: \.self) { item in
			                        Button {
			                            vm.codeHex = item.components(separatedBy: " ").first ?? item
			                            isTextFieldFocused = false
			                        } label: {
			                            HStack {
			                                Text(item)
			                                    .foregroundColor(.primary)
			                                Spacer()
			                            }
			                            .padding(.horizontal, 12)
			                            .padding(.vertical, 10)
			                            .background(Color.white)
			                        }
			                        .buttonStyle(.plain)

			                        Divider()
			                    }
			                }
			            }
                    }

                    HStack {
						TextField("", text: $vm.dpParams, axis: .vertical)
			                .textFieldStyle(.roundedBorder)
						    .lineLimit(5...20)
					}
					if vm.canSendCommand && (vm.modeInput != .Disabled) {
	                    HStack {
							if vm.modeInput == .DP {
			                    Button("min") { vm.setDP(.Min) }
			                    Button("dec") { vm.setDP(.Dec) }
			                    Button("inc") { vm.setDP(.Inc) }
			                    Button("max") { vm.setDP(.Max) }
							} else {
			                    Button("set(1)") { vm.setCC(1) }
			                    Button("set(2)") { vm.setCC(2) }
							}
	                        Text(" ")

	                        TextField("0000", text: $vm.dpSetVal)
				                .textFieldStyle(.roundedBorder)
				                .frame(width: 100)
				                .onSubmit {
				                	vm.setDPCC()
				            	}
		                    Button("set") { vm.setDPCC() }
						}
                    }
                } // VStack
            } // GroupBox

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
        } // VStack
    } // body
}

#Preview {
    ContentView()
}