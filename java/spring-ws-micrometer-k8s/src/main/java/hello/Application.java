package hello;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Import;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Random;

import io.micrometer.core.annotation.Timed;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.Metrics;

@SpringBootApplication
@RestController
@Import({ApplicationConfiguration.class})
public class Application {

    private static long SLEEP_LOWER_MS = 100;
    private static long SLEEP_UPPER_MS = 300;

    private Counter exceptionCounter;

    @Autowired
    public Application() {
        exceptionCounter = Metrics.counter("home_exception");
    }

    @Timed(value = "application.home")
    @RequestMapping("/")
    public String home() {

        long randomSleepMs = SLEEP_LOWER_MS + (long) (new Random().nextFloat() * (SLEEP_UPPER_MS - SLEEP_LOWER_MS));

        // for experiment, throw an exception whenever random sleep ms ends with 1
        if (randomSleepMs % 10 == 1) {
            exceptionCounter.increment();
            throw new RuntimeException("hit planned test error with random sleep: " + randomSleepMs);
        }

        try {
            Thread.sleep(randomSleepMs);
        } catch (InterruptedException e) {
            System.out.print("Not expect to get here");
        }

        return "Slept for " + randomSleepMs + "ms";
    }

    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }

}
