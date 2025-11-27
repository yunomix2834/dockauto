package com.example.demo;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

/**
 * "Integration" test fake:
 * - Chỉ kiểm tra ENV do infra cung cấp:
 *   DB_HOST, REDIS_HOST, ...
 * - Khi chạy qua dockauto với infra, các env này đã được map.
 */
public class IntegrationDemoTests {

    @Test
    void shouldSeeDbAndRedisEnv() {
        String dbHost = System.getenv("DB_HOST");
        String redisHost = System.getenv("REDIS_HOST");

        assertNotNull(dbHost, "DB_HOST must not be null in integration tests");
        assertNotNull(redisHost, "REDIS_HOST must not be null in integration tests");
    }

    @Test
    void appEnvShouldBeDevelopment() {
        String appEnv = System.getenv("APP_ENV");
        assertEquals("development", appEnv, "APP_ENV should be 'development' in dev profile");
    }
}