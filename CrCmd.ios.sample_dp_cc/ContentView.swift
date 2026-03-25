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
/*
        "0001 (data1)",
        "0002 (data2)",
        "0003 (data3)",
        "0001 (data1)",
        "0002 (data2)",
        "0003 (data3)"
*/
    ]

    var filteredCandidates: [String] {
        return candidates
    }

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
                        Button("connect") {
                            vm.connect()
                        }
                        .disabled(!vm.hasCamera)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("PTP Commands") {
                VStack(alignment: .leading, spacing: 12) {

                    HStack {
                        Text("DP 0x")
			            TextField("0000", text: $vm.dpCodeHex)
			                .textFieldStyle(RoundedBorderTextFieldStyle())
			                .textInputAutocapitalization(.characters)
			                .focused($isTextFieldFocused)

			            if isTextFieldFocused {
			                VStack(spacing: 0) {
			                    ForEach(filteredCandidates, id: \.self) { item in
			                        Button {
			                            vm.dpCodeHex = item.components(separatedBy: " ").first ?? item
			                            isTextFieldFocused = false

					                    if vm.canSendCommand {
					                    	vm.updatedp()
					                    }
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
			                .background(Color.white)
			                .overlay(
			                    RoundedRectangle(cornerRadius: 8)
			                        .stroke(Color.gray.opacity(0.3))
			                )
			                .cornerRadius(8)
			            }

                    }

                    HStack {
	                    Button("set") {
	                        vm.setdp()
	                    }
	                    .disabled(!vm.canSendCommand)

                        TextField("0000", text: $vm.dpSetVal)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textInputAutocapitalization(.characters)
                    }

                    HStack {
	                    Button("update") {
	                        vm.updatedp()
	                    }
	                    .disabled(!vm.canSendCommand)

						TextField("xx", text: $vm.dpParams, axis: .vertical)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
						    .lineLimit(10...20)
                            .textInputAutocapitalization(.characters)
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