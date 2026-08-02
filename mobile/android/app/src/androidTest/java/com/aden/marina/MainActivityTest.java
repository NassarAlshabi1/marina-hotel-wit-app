// ════════════════════════════════════════════════════════════════════════════
//  Marina Hotel — Patrol Android Test Runner
//  ════════════════════════════════════════════════════════════════════════════
//
//  هذا الملف هو الجسر بين JUnit واختبارات Dart المكتوبة بـ Patrol.
//  PatrolJUnitRunner يُحمِّل كل اختبارات Dart ديناميكياً ويُشغِّلها كـ JUnit cases.
//
//  المرجع: https://patrol.leancode.co/documentation#android-setup
// ════════════════════════════════════════════════════════════════════════════

package com.aden.marina;

import androidx.test.platform.app.InstrumentationRegistry;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.junit.runners.Parameterized;
import org.junit.runners.Parameterized.Parameters;
import pl.leancode.patrol.PatrolJUnitRunner;

@RunWith(Parameterized.class)
public class MainActivityTest {

    @Parameters(name = "{0}")
    public static Object[] testCases() {
        PatrolJUnitRunner instrumentation = (PatrolJUnitRunner) InstrumentationRegistry.getInstrumentation();
        instrumentation.setUp(MainActivity.class);
        instrumentation.waitForPatrolAppService();
        return instrumentation.listDartTests();
    }

    public MainActivityTest(String dartTestName) {
        this.dartTestName = dartTestName;
    }

    private final String dartTestName;

    @Test
    public void runDartTest() {
        PatrolJUnitRunner instrumentation = (PatrolJUnitRunner) InstrumentationRegistry.getInstrumentation();
        instrumentation.runDartTest(dartTestName);
    }
}
