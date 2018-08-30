package hello;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import io.micrometer.core.aop.TimedAspect;
import io.micrometer.core.instrument.Clock;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.statsd.StatsdConfig;
import io.micrometer.statsd.StatsdFlavor;
import io.micrometer.statsd.StatsdMeterRegistry;

@Configuration
public class ApplicationConfiguration {

    @Bean
    public MeterRegistry meterRegistry() {
        StatsdConfig config = new StatsdConfig() {
            @Override
            public String get(String k) {
                return null;
            }


            @Override
            public StatsdFlavor flavor() {
                return StatsdFlavor.DATADOG;
            }
        };

        MeterRegistry registry = new StatsdMeterRegistry(config, Clock.SYSTEM);
        return registry;
    }

    @Bean
    @Autowired
    public TimedAspect timedAspect(MeterRegistry registry) {
        return new TimedAspect(registry);
    }

}
