import SwiftUI

struct EulaView: View {
    @AppStorage("eulaAccepted") private var eulaAccepted = false

    var body: some View {
        VStack(spacing: 20) {
            Text("EULA")
                .font(.title)
                .bold()

            ScrollView {
            	Text("""
                \(Text("Using this app to control a Sony camera, the camera will be out of Sony manufacturer-warranty.").bold())
                Please use this app only if you understand and accept this condition.

                This app uses Sony’s Camera Remote Command library and was developed by Sohta-Mei.
                The above terms are based on the Sony Library Terms of Use.
                Additionally, this app cannot be used for critical applications such as life-support systems or military purposes.
                Sohta-Mei and Sony shall not be liable for any damage, including camera malfunction or failure, caused by the use of this app.
                """)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .border(Color.gray)

            Button("Accept") {
                eulaAccepted = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#Preview {
    EulaView()
}
