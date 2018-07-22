package hello;

import io.micrometer.core.aop.TimedAspect;
import io.micrometer.core.instrument.Clock;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.composite.CompositeMeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import io.micrometer.statsd.StatsdConfig;
import io.micrometer.statsd.StatsdFlavor;
import io.micrometer.statsd.StatsdMeterRegistry;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

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

        CompositeMeterRegistry meterRegistry = new CompositeMeterRegistry();
        meterRegistry.add(new StatsdMeterRegistry(config, Clock.SYSTEM));
        meterRegistry.add(new SimpleMeterRegistry());

        return meterRegistry;
    }

    @Bean
    @Autowired
    public TimedAspect timedAspect(MeterRegistry registry) {
        return new TimedAspect(registry);
    }

}
