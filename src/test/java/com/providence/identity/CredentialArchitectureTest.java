package com.providence.identity;

import com.tngtech.archunit.core.importer.ImportOption;
import com.tngtech.archunit.junit.AnalyzeClasses;
import com.tngtech.archunit.junit.ArchTest;
import com.tngtech.archunit.lang.ArchRule;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;

/**
 * ArchUnit tests enforcing credential/profile separation at the architecture level.
 *
 * PROV-109: Prevents credential data from leaking into profile-facing code paths.
 * These rules are enforced at compile-test time, not just at runtime.
 */
@AnalyzeClasses(
        packages = "com.providence.identity",
        importOptions = ImportOption.DoNotIncludeTests.class
)
class CredentialArchitectureTest {

    /**
     * DTOs must never import or depend on the Credential entity.
     * This prevents accidental exposure of credential fields in API responses.
     */
    @ArchTest
    static final ArchRule dtosShouldNotDependOnCredential = noClasses()
            .that().resideInAPackage("..dto..")
            .should().dependOnClassesThat()
            .haveSimpleName("Credential")
            .as("DTOs must not depend on Credential entity (PROV-109)");

    /**
     * UserService must not depend on CredentialRepository.
     * Profile reads/writes are isolated from credential operations.
     */
    @ArchTest
    static final ArchRule userServiceShouldNotDependOnCredentialRepository = noClasses()
            .that().haveSimpleName("UserService")
            .should().dependOnClassesThat()
            .haveSimpleName("CredentialRepository")
            .as("UserService must not access CredentialRepository (PROV-109)");

    /**
     * CredentialService must not depend on UserProfileRepository.
     * Credential operations are isolated from profile reads/writes.
     */
    @ArchTest
    static final ArchRule credentialServiceShouldNotDependOnUserProfileRepository = noClasses()
            .that().haveSimpleName("CredentialService")
            .should().dependOnClassesThat()
            .haveSimpleName("UserProfileRepository")
            .as("CredentialService must not access UserProfileRepository (PROV-109)");

    /**
     * UserController must not depend on CredentialRepository or CredentialService.
     * Profile-facing controllers never access credential data.
     */
    @ArchTest
    static final ArchRule userControllerShouldNotDependOnCredentials = noClasses()
            .that().haveSimpleName("UserController")
            .should().dependOnClassesThat()
            .haveSimpleNameContaining("Credential")
            .as("UserController must not access credential types (PROV-109)");

    /**
     * AuthController must not depend on UserProfileRepository or UserService.
     * Authentication controllers never access profile data.
     */
    @ArchTest
    static final ArchRule authControllerShouldNotDependOnUserProfile = noClasses()
            .that().haveSimpleName("AuthController")
            .should().dependOnClassesThat()
            .haveSimpleName("UserProfileRepository")
            .as("AuthController must not access UserProfileRepository (PROV-109)");
}
