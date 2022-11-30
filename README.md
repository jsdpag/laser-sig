# Laser Signals

Collection of custom TDT Synapse Gizmos and Matlab SynapseAPI code for convenient real-time parameter setting and generation of analogue and TTL signals used to drive up to two different lasers.

## LaserTester.rcx

Manual control of Voltage output and TTL signals. Two sets of analogue/TTL output channels mean that two separate lasers can be tested in one session.

## LaserSignal.rcx

For automated control of up to two lasers in a single session. This is capable of generating scaled and shifted sinusoidal analogue output. The sinusoid is phase-shifted by -90 degrees, so that it starts at the minimum and immediately rises towards the peak. Simple scale and baseline terms are used to set the peak to peak Voltage of the laser's analogue input. The duration of emission is also controlled by an internal timer; once the timer runs out, then the voltage output returns to zero. The output is zeroed as soon as an abort signal arrives, regardless of the timer. The timer is reset and started as soon as a new start signal is received. A Rise/Fall time can be used to latch the sinusoid for a duration centred in the middle of the timing window. For instance, this can be used to create a sinusoidal rise to peak, and then to hold that peak value until a final, sinusoidal fall to minimum. Such an approach may be useful in opto-tagging. A TTL control signal is generated that is high for the entire duration of the laser emission, regardless of the value of the analogue signal. The TTL signal is low at all other times.

## LaserSignal.m

MATLAB class for setting control parameters of the LaserSignal.rcx Synapse Gizmo from a remote PC. E.g. LaserSignal.m can be used in an ARCADE task script, when Synapse and ARCADE run on separate PCs. An instance of this class is uniquely linked to a given instance of the LaserSignal.rcx Gizmo that is visible in the current Synapse experiment. LaserSignal.m object parameters correspond to those in the Gizmo. However, the units are more intuitive e.g. using milliseconds for the Time parameter, rather than number of samples. In addition, LaserSignal.m can toggle a 'plateau' mode on or off, in which the first and last peak of the sinusoidal voltage trace are either linked by a flat line (plateau on) or not (plateau off); in the latter case, the complete sinusoid is output by the Gizmo.

## LaserController.rcx

The LaserController Gizmo is intended to control the joint timing of the LaserSignal Gizmo and event-triggered buffering Gizmos. It can initiate both processes based on an incoming 16-bit event code. Optionally, it can also wait for a visual photodiode trace to cross a threshold. Hence, the timing of the laser emission and the buffering can be triggered at an arbitrary time, or locked to a visual event on the stimulus monitor.
  
The photodiode signal must cross a set threshold in a specific direction (rising or falling through). In addition, all further threshold crossings will be ignored for a set duration, to filter out possible noise.
  
A delay can be imposed upon the onset of the laser emission. This might be needed to simulate the visual latency of the target site when triggering the laser and buffer with a visual event. However, the buffering trigger will always occur as soon as the necessary event marker and photodiode conditions are satisfied.
  
Optionally, the laser onset event markers can be ignored in favour of a manual trigger button presented by Synapse.
  
A liberal laser de-activation signal is triggered in response to one of three possible events. Two event marker codes can be tested for. One can be a late but guaranteed event e.g. end of trial. The second can be an early but optional event e.g. behavioural response. The third possibility is the release of the manual trigger button.

## LaserController.m

Matlab class that uses SynapseAPI to set parameters in a named LaserController.rcx Gizmo.

## LaserSignalBuffer.rcx

This maintains a memory buffer on the TDT Sys3 hardware that can be loaded via SynapseAPI. This allows for any arbitrary signal to be loaded for triggered playback. A safety feature includes a timer that stops playback after a given duration. The sampling rate of the output can be set, within the limitations of the TDT hardware sampling rate. The buffered signal plays as a floating point LaserSignal output. When the signal is playing, the LaserEnable logical value is high; otherwise it is low.

## LaserSignalBuffer.m

MATLAB class for remote communication with the LaserSignalBuffer.rcx Gizmo. Loading a signal into the Gizmo's buffer is done simply by a standard MATLAB assignment statement to the .Signal parameter e.g. sigbuf.Signal = sin( 2*pi*30 * (1 : 508) / sigbuf.FsSample + 1.5 * pi ) ;

## LaserSignalSwitch

Synapse Gizmo for channeling the output of LaserSignalBuffer.rcx towards one pair of system outputs or another. Thus, at least two separate lasers can exclusively receive the laser signal and enable lines. The other receives only zero-valued signals. 

## LaserInputOutputMeasure.m

Partially or fully automate the measurement of a laser's transfer function. The input to the laser is a constant analogue voltage. The output is the measured power of the laser's emission, in milliWatts. Uses SynapseAPI to control analogue voltage control signals via a named LaserTester.rcx Gizmo. Optionally, it can be configured to read the analoge voltage output of a power meter e.g. a PM100D in order to further automate measurement.

## transfer.m

Laser transfer function, computing power output (e.g. in mW) from given analogue voltage input (e.g. in Volts). Also implements the inverse transfer function. Models initial relationship as a power function that switches to a linear relationship above a given input threshold. This sort of function is suitable for modelling input/output relationship of a diode laser such as the Omicron Laserage LuxX+. To set the laser at a specific value, use the inverse function to get the required input for the laser.

## transcoef.m

A convenience function that finds the best-fitting set of coefficients for the laser transfer function transfer( ) using least-squares, non-linear regression.

## makelasertable.m

Helper function that partially automates the process of measuring and estimating the transfer function for a set of lasers. The results are written to ASCII CSV files that can readily be imported for use into e.g. an ARCADE task for setting laser parameters using the laser-signals library.

