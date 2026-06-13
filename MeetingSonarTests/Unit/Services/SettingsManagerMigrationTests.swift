//
//  SettingsManagerMigrationTests.swift
//  MeetingSonarTests
//
//  F-0.10.2: Teams Detection Migration Tests
//  Tests for unified Teams detection toggle migration logic
//

import Testing
import Foundation
@preconcurrency import XCTest
@testable import MeetingSonar

@Suite("SettingsManager Migration Tests", .serialized)
@MainActor
struct SettingsManagerMigrationTests {

    // MARK: - Properties

    private let migrationKey = "hasMigratedTeamsDetection"
    private let classicKey = "detectTeamsClassic"
    private let newKey = "detectTeamsNew"

    // MARK: - Helper Methods

    /// Reset migration state for testing
    private func resetMigrationState() {
        UserDefaults.standard.removeObject(forKey: migrationKey)
        UserDefaults.standard.removeObject(forKey: classicKey)
        UserDefaults.standard.removeObject(forKey: newKey)
    }

    /// Set up pre-migration state
    private func setPreMigrationState(classic: Bool, new: Bool) {
        resetMigrationState()
        UserDefaults.standard.set(classic, forKey: classicKey)
        UserDefaults.standard.set(new, forKey: newKey)
    }

    // MARK: - F-0.10.2: Teams Detection Migration Tests

    @Test("Migration: classic=true, new=false -> Teams New becomes true")
    func testMigrationClassicTrueNewFalse() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original values
            let originalClassic = settings.detectTeamsClassic
            let originalNew = settings.detectTeamsNew

            // Set up pre-migration state
            setPreMigrationState(classic: true, new: false)

            // Reset migration flag to allow re-migration
            UserDefaults.standard.removeObject(forKey: migrationKey)

            // Run migration
            settings.migrateTeamsDetection()

            // Classic-only legacy users should keep Teams support through Teams New.
            #expect(UserDefaults.standard.bool(forKey: classicKey) == false)
            #expect(UserDefaults.standard.bool(forKey: newKey) == true)

            // Restore originals
            settings.detectTeamsClassic = originalClassic
            settings.detectTeamsNew = originalNew
        }
    }

    @Test("Migration: classic=false, new=true -> Teams New remains true")
    func testMigrationClassicFalseNewTrue() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original values
            let originalClassic = settings.detectTeamsClassic
            let originalNew = settings.detectTeamsNew

            // Set up pre-migration state
            setPreMigrationState(classic: false, new: true)

            // Reset migration flag to allow re-migration
            UserDefaults.standard.removeObject(forKey: migrationKey)

            // Run migration
            settings.migrateTeamsDetection()

            // Classic stays disabled; Teams New remains active.
            #expect(UserDefaults.standard.bool(forKey: classicKey) == false)
            #expect(UserDefaults.standard.bool(forKey: newKey) == true)

            // Restore originals
            settings.detectTeamsClassic = originalClassic
            settings.detectTeamsNew = originalNew
        }
    }

    @Test("Migration: both false -> Teams New remains false")
    func testMigrationBothFalse() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original values
            let originalClassic = settings.detectTeamsClassic
            let originalNew = settings.detectTeamsNew

            // Set up pre-migration state
            setPreMigrationState(classic: false, new: false)

            // Reset migration flag to allow re-migration
            UserDefaults.standard.removeObject(forKey: migrationKey)

            // Run migration
            settings.migrateTeamsDetection()

            // Verify active Teams New remains false.
            #expect(UserDefaults.standard.bool(forKey: classicKey) == false)
            #expect(UserDefaults.standard.bool(forKey: newKey) == false)

            // Restore originals
            settings.detectTeamsClassic = originalClassic
            settings.detectTeamsNew = originalNew
        }
    }

    @Test("Migration: both true -> Teams New remains true")
    func testMigrationBothTrue() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original values
            let originalClassic = settings.detectTeamsClassic
            let originalNew = settings.detectTeamsNew

            // Set up pre-migration state
            setPreMigrationState(classic: true, new: true)

            // Reset migration flag to allow re-migration
            UserDefaults.standard.removeObject(forKey: migrationKey)

            // Run migration
            settings.migrateTeamsDetection()

            // Classic is retired; Teams New remains active.
            #expect(UserDefaults.standard.bool(forKey: classicKey) == false)
            #expect(UserDefaults.standard.bool(forKey: newKey) == true)

            // Restore originals
            settings.detectTeamsClassic = originalClassic
            settings.detectTeamsNew = originalNew
        }
    }

    @Test("Migration is idempotent - running multiple times has same result")
    func testMigrationIdempotency() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original values
            let originalClassic = settings.detectTeamsClassic
            let originalNew = settings.detectTeamsNew

            // Set up pre-migration state
            setPreMigrationState(classic: true, new: false)

            // Reset migration flag to allow re-migration
            UserDefaults.standard.removeObject(forKey: migrationKey)

            // Run migration multiple times
            settings.migrateTeamsDetection()
            settings.migrateTeamsDetection()
            settings.migrateTeamsDetection()

            // Verify result is consistent.
            #expect(UserDefaults.standard.bool(forKey: classicKey) == false)
            #expect(UserDefaults.standard.bool(forKey: newKey) == true)

            // Restore originals
            settings.detectTeamsClassic = originalClassic
            settings.detectTeamsNew = originalNew
        }
    }

    @Test("Migration flag prevents re-migration")
    func testMigrationFlagPreventsReMigration() async throws {
        await MainActor.run {
            let settings = SettingsManager.shared

            // Save original values
            let originalClassic = settings.detectTeamsClassic
            let originalNew = settings.detectTeamsNew

            // Set up pre-migration state
            setPreMigrationState(classic: true, new: false)

            // First migration - should run
            settings.migrateTeamsDetection()
            #expect(UserDefaults.standard.bool(forKey: migrationKey) == true)

            // Change values to test re-migration prevention
            UserDefaults.standard.set(false, forKey: classicKey)
            UserDefaults.standard.set(false, forKey: newKey)

            // Second migration - should be skipped
            settings.migrateTeamsDetection()

            // Values should remain false (not re-migrated to true)
            #expect(UserDefaults.standard.bool(forKey: classicKey) == false)
            #expect(UserDefaults.standard.bool(forKey: newKey) == false)

            // Restore originals
            settings.detectTeamsClassic = originalClassic
            settings.detectTeamsNew = originalNew
        }
    }
}
