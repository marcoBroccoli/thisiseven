#if os(iOS)
    import SwiftUI
    import UIKit

    /// Thin `UIImagePickerController` bridge — SwiftUI has no native camera capture view.
    struct CameraCapture: UIViewControllerRepresentable {
        @Binding var isPresented: Bool
        var onCapture: (Data) -> Void

        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = context.coordinator
            return picker
        }

        func updateUIViewController(_: UIImagePickerController, context _: Context) {}

        func makeCoordinator() -> Coordinator {
            Coordinator(parent: self)
        }

        final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
            let parent: CameraCapture

            init(parent: CameraCapture) {
                self.parent = parent
            }

            func imagePickerController(
                _: UIImagePickerController,
                didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
            ) {
                if let image = info[.originalImage] as? UIImage,
                   let data = image.jpegData(compressionQuality: 0.9) {
                    parent.onCapture(data)
                }
                parent.isPresented = false
            }

            func imagePickerControllerDidCancel(_: UIImagePickerController) {
                parent.isPresented = false
            }
        }
    }
#endif
