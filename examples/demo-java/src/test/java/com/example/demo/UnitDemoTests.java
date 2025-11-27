package com.example.demo;

import com.example.demo.controller.HelloController;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

public class UnitDemoTests {

    @Test
    void simpleUnitTest() {
        HelloController c = new HelloController();
        assertEquals("Hello from dockauto demo", c.hello());
    }
}