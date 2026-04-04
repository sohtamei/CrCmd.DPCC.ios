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
                xxx
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
