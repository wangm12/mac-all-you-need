import Core
import SwiftUI

struct AIFileOrganizerPage: View {
    let controller: AppController

    var body: some View {
        FileOrganizerPage(coordinator: controller.fileOrganizerCoordinator, controller: controller)
    }
}
