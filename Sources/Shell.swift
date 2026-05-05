import Foundation

private let toolPaths = "/opt/homebrew/bin:/usr/local/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin:/Users/\(NSUserName())/Library/Python/3.9/bin:/Users/\(NSUserName())/Library/Python/3.11/bin:/Users/\(NSUserName())/Library/Python/3.12/bin"

@discardableResult
func shell(_ command: String) -> String {
    let task = Process()
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    task.arguments = ["-c", command]
    task.environment = ProcessInfo.processInfo.environment.merging(
        ["PATH": toolPaths]
    ) { _, new in new }

    do {
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    } catch {
        return ""
    }
}

func shellAsync(_ command: String, completion: @escaping (String) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let result = shell(command)
        DispatchQueue.main.async { completion(result) }
    }
}
