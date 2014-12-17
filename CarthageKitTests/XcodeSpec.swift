//
//  XcodeSpec.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-11.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import LlamaKit
import Nimble
import Quick
import ReactiveCocoa
import ReactiveTask

class XcodeSpec: QuickSpec {
	override func spec() {
		let directoryURL = NSBundle(forClass: self.dynamicType).URLForResource("ReactiveCocoaLayout", withExtension: nil)!
		let workspaceURL = directoryURL.URLByAppendingPathComponent("ReactiveCocoaLayout.xcworkspace")
		let buildFolderURL = directoryURL.URLByAppendingPathComponent(CarthageBinariesFolderName)
		let targetFolderURL = NSURL(fileURLWithPath: NSTemporaryDirectory().stringByAppendingPathComponent(NSProcessInfo.processInfo().globallyUniqueString), isDirectory: true)!

		beforeEach {
			NSFileManager.defaultManager().removeItemAtURL(buildFolderURL, error: nil)
			NSFileManager.defaultManager().createDirectoryAtPath(targetFolderURL.path!, withIntermediateDirectories: true, attributes: nil, error: nil)
			return ()
		}

		it("should build for all platforms") {
			let dependencies = [
				ProjectIdentifier.GitHub(GitHubRepository(owner: "github", name: "Archimedes")),
				ProjectIdentifier.GitHub(GitHubRepository(owner: "ReactiveCocoa", name: "ReactiveCocoa")),
			]

			for project in dependencies {
				let (outputSignal, schemeSignals) = buildDependencyProject(project, directoryURL, withConfiguration: "Debug")
				let result = schemeSignals
					.concat(identity)
					.on(next: { (project, scheme) in
						NSLog("Building scheme \"\(scheme)\" in \(project)")
					})
					.wait()

				expect(result.error()).to(beNil())
			}

			let (outputSignal, schemeSignals) = buildInDirectory(directoryURL, withConfiguration: "Debug")
			let result = schemeSignals
				.concat(identity)
				.on(next: { (project, scheme) in
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()

			expect(result.error()).to(beNil())

			// Verify that the build products exist at the top level.
			var projectNames = dependencies.map { project in project.name }
			projectNames.append("ReactiveCocoaLayout")

			for dependency in projectNames {
				let macPath = buildFolderURL.URLByAppendingPathComponent("Mac/\(dependency).framework").path!
				let iOSPath = buildFolderURL.URLByAppendingPathComponent("iOS/\(dependency).framework").path!

				var isDirectory: ObjCBool = false
				expect(NSFileManager.defaultManager().fileExistsAtPath(macPath, isDirectory: &isDirectory)).to(beTruthy())
				expect(isDirectory).to(beTruthy())

				expect(NSFileManager.defaultManager().fileExistsAtPath(iOSPath, isDirectory: &isDirectory)).to(beTruthy())
				expect(isDirectory).to(beTruthy())
			}

			let frameworkFolderURL = buildFolderURL.URLByAppendingPathComponent("iOS/ReactiveCocoaLayout.framework")

			// Verify that the iOS framework is a universal binary for device
			// and simulator.
			let architectures = architecturesInFramework(frameworkFolderURL)
				.first()
				.value()!

			expect(architectures).to(contain("i386"))
			expect(architectures).to(contain("armv7"))
			expect(architectures).to(contain("arm64"))

			// Verify that our dummy framework in the RCL iOS scheme built as
			// well.
			let auxiliaryFrameworkPath = buildFolderURL.URLByAppendingPathComponent("iOS/AuxiliaryFramework.framework").path!
			var isDirectory: ObjCBool = false
			expect(NSFileManager.defaultManager().fileExistsAtPath(auxiliaryFrameworkPath, isDirectory: &isDirectory)).to(beTruthy())
			expect(isDirectory).to(beTruthy())

			// Copy ReactiveCocoaLayout.framework to the temporary folder.
			let targetURL = targetFolderURL.URLByAppendingPathComponent("ReactiveCocoaLayout.framework", isDirectory: true)

			println(targetURL)

			copyFramework(frameworkFolderURL, targetURL).wait()

			expect(NSFileManager.defaultManager().fileExistsAtPath(targetURL.path!, isDirectory: &isDirectory)).to(beTruthy())
			expect(isDirectory).to(beTruthy())

			stripArchitecture(targetURL, "i386").wait()

			let stripped = architecturesInFramework(targetURL)
				.first()
				.value()!

			expect(stripped).notTo(contain("i386"))

			codesign(targetURL, "-").wait()

			var output: String = ""
			let codeSign = TaskDescription(launchPath: "/usr/bin/codesign", arguments: [ "--verify", "--verbose", targetURL.path! ])

			launchTask(codeSign, standardError: SinkOf<NSData> { data -> () in
				output += NSString(data: data, encoding: NSStringEncoding(NSUTF8StringEncoding))!
			}).wait()

			expect(output).to(contain("satisfies its Designated Requirement"))
		}

		it("should locate the workspace") {
			let result = locateProjectsInDirectory(directoryURL).first()
			expect(result.error()).to(beNil())

			let locator = result.value()!
			expect(locator).to(equal(ProjectLocator.Workspace(workspaceURL)))
		}

		it("should locate the project from the parent directory") {
			let result = locateProjectsInDirectory(directoryURL.URLByDeletingLastPathComponent!).first()
			expect(result.error()).to(beNil())

			let locator = result.value()!
			expect(locator).to(equal(ProjectLocator.Workspace(workspaceURL)))
		}

		it("should not locate the project from a directory not containing it") {
			let result = locateProjectsInDirectory(directoryURL.URLByAppendingPathComponent("ReactiveCocoaLayout")).first()
			expect(result.value()).to(beNil())
		}
	}
}
