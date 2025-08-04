import Foundation
if #available(macOS 13, *) {
    Task {
        await runMain()
    }
}
else
{
    print("Only supported on MacOS 13 and onwards.")
}

// Keep the process alive
RunLoop.main.run()