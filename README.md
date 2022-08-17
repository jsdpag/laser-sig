# Laser Signals

Collection of custom TDT Synapse Gizmos and Matlab SynapseAPI code for convenient real-time parameter setting and generation of analogue and TTL signals used to drive up to two different lasers.

## LaserTester.rcx

Manual control of Voltage output and TTL signals. Two sets of analogue/TTL output channels mean that two separate lasers can be tested in one session.

## LaserSignal.rcx

For automated control of up to two lasers in a single session. This is capable of generating scaled and shifted sinusoidal analogue output. The sinusoid is phase-shifted by -90 degrees, so that it starts at the minimum and immediately rises towards the peak. Scaling/shifting values can be set separately for each laser. Values can be chosen so that the two lasers span the same power output range (in mW). A pre-amp control can then be used to change the peak amplitude of either laser within that range. One may specify the exact DAQ event markers that start/abort laser emission. The duration of emission is also controlled by an internal timer; once the timer runs out, then the voltage output returns to zero. The output is zeroed as soon as an abort signal arrives, regardless of the timer. A mandatory abort signal must follow each phase of laser emission before another DAQ start signal will trigger emissions, anew. The timer is reset and started as soon as a valid DAQ start signal is received. A Rise/Fall time can be used to latch the sinusoid for a duration centred in the middle of the timing window. For instance, this can be used to create a sinusoidal rise to peak, and then to hold that peak value until a final, sinusoidal fall to minimum. Such an approach may be useful in opto-tagging. A TTL control signal is generated that is high for the entire duration of the laser emission, regardless of the value of the analogue signal. The TTL signal is low at all other times.
