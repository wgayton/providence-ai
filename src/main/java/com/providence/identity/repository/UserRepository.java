package com.providence.identity.repository;

import com.providence.identity.domain.User;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

/**
 * Repository for User aggregate root.
 * Queries scoped to tenant schema via Hibernate multi-tenancy.
 */
public interface UserRepository extends JpaRepository<User, UUID> {
}
