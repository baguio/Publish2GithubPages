import Publish
import ShellOut
import Foundation

struct PublishToGitHubPages {
    var text = "Hello, World!"
}

public extension DeploymentMethod {
    private static func _git(_ remote: String, branch: String = "master", outputFolderPath: Path? = nil, context: PublishingContext<Site>) throws {
        let folder = try context.createDeploymentFolder(withPrefix: "Git", outputFolderPath: outputFolderPath) { folder in
            try folder.empty(includingHidden: true)

            try shellOut(to: .gitInit(), at: folder.path)

            try shellOut(to: "git remote add origin \(remote)", at: folder.path)

            try shellOut(to: "git fetch", at: folder.path)

            if outputFolderPath != nil {
                try shellOut(
                    to: "git checkout \(branch) || git checkout -b \(branch)",
                    at: folder.path
                )
            } else {
                try shellOut(
                    to: "git symbolic-ref HEAD refs/remotes/origin/\(branch)",
                    at: folder.path
                )
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let dateString = dateFormatter.string(from: Date())

        do {
            try shellOut(
                to: """
                git add . && git commit -a -m \"Publish deploy \(dateString)\" --allow-empty
                """,
                at: folder.path
            )

            if outputFolderPath == nil {
                try shellOut(to: "git checkout -b \(branch)", at: folder.path)
            }

            try shellOut(to: "git push origin \(branch)", at: folder.path)
        } catch let error as ShellOutError {
            throw PublishingError(infoMessage: error.message)
        } catch {
            throw error
        }
    }
    
    private static func _gitHub(_ repository: String, branch: String = "master", outputFolderPath: Path? = nil, useSSH: Bool = true, context: PublishingContext<Site>) throws {
        try _git(gitHubRemote(repository: repository, useSSH: useSSH),
                 branch: branch, outputFolderPath: outputFolderPath,
                 context: context)
    }
    
    
    /// Deploy a website using GitHub Pages.
    /// - parameter repository: The full name of the repository (including its username).
    /// - parameter source: The publishing source for your GitHub Pages site.
    ///   This should be set in your repository settings.
    /// - parameter useSSH: Whether an SSH connection should be used (preferred).
    static func gitHubPages(_ repository: String,
                            source: GitHubPagesDeploymentMode = .master,
                            useSSH: Bool = true)
        -> Self
    {
        let remote = gitHubRemote(repository: repository, useSSH: useSSH)
        
        return DeploymentMethod(name: "GitHub Pages (\(remote))") { context in
            let jekyllDisablingFile = try context.createOutputFile(at: Path(".nojekyll"))
            
            let branchName : String
            var outputFolderPath: Path? = nil
            
            switch source {
            case .ghPages :
                branchName = "gh-pages"
            case .masterDocs :
                outputFolderPath = Path("docs")
                fallthrough
            case .master :
                branchName = "master"
            }
            
            try _gitHub(repository,
                       branch: branchName,
                       outputFolderPath: outputFolderPath,
                       useSSH: useSSH,
                       context: context)
            
            try jekyllDisablingFile.delete()
            
            let ghPagesModeName : String
            switch source {
            case .master : ghPagesModeName = "master branch"
            case .masterDocs : ghPagesModeName = "master branch /docs folder"
            case .ghPages : ghPagesModeName = "gh-pages branch"
            }
            
            let settingsURL = "\(gitHubRemote(repository: repository, useSSH: false, useStandardRepoURL: false))/settings"
            
            CommandLine.output("Remember to set your GitHub Pages source to \"\(ghPagesModeName)\" at \(settingsURL)")
        }
    }
    
    private static func gitHubRemote(repository: String, useSSH: Bool, useStandardRepoURL: Bool = true) -> String {
        let prefix = useSSH ? "git@github.com:" : "https://github.com/"
        let suffix = useStandardRepoURL ? ".git" : ""
        return "\(prefix)\(repository)\(suffix)"
    }
    
    enum GitHubPagesDeploymentMode {
        case master, ghPages, masterDocs
    }
}

private extension CommandLine {
    static func output(_ string: String) {
        fputs(string + "\n", stdout)
    }
}
