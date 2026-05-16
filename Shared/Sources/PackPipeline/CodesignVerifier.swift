import Foundation
import Security

public enum CodesignVerifier {
    public static func verify(fileAt url: URL, requirement: String) throws {
        var staticCode: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard status == errSecSuccess, let code = staticCode else {
            throw PackPipelineError.codesignFailed(
                name: url.lastPathComponent,
                reason: "SecStaticCodeCreateWithPath status \(status)"
            )
        }

        var requirementRef: SecRequirement?
        status = SecRequirementCreateWithString(requirement as CFString, [], &requirementRef)
        guard status == errSecSuccess, let req = requirementRef else {
            throw PackPipelineError.codesignFailed(
                name: url.lastPathComponent,
                reason: "SecRequirementCreateWithString status \(status)"
            )
        }

        var checkError: Unmanaged<CFError>?
        let flags = SecCSFlags(rawValue: SecCSFlags.RawValue(kSecCSCheckAllArchitectures | kSecCSCheckNestedCode))
        status = SecStaticCodeCheckValidityWithErrors(code, flags, req, &checkError)
        if status != errSecSuccess {
            let detail = checkError.map { "\($0.takeRetainedValue())" } ?? "status \(status)"
            throw PackPipelineError.codesignFailed(name: url.lastPathComponent, reason: detail)
        }
    }
}
