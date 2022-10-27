
function  in2out = LaserInputOutputMeasure( varargin )
% 
% in2out = LaserInputOutputMeasure( [ 'Name' , <value> ] )
% 
% Partially or fully automate the measurement of a laser's transfer
% function. The input to the laser is a constant analogue voltage. The
% output is the measured power of the laser's emission, in milliWatts.
% 
% Returns struct in2out with fields .input_V and .output_mW containing the
% input voltages and the resulting mW of output. Both are row vectors
% with the same length where the ith element of in2out.input_V is in
% register with the ith element of in2out.output_mW such that input
% voltage in2out.input_V( i ) resulted in an emission with an output power
% of in2out.output_mW( i ).
% 
% Operation of this function requires that the Tucker Davis Technologies
% library TDTMatlabSDK is visible on the path, and that Matlab is
% connected in some way to TDT's Synapse application, either locally or via
% a network. Synapse API is used to query the status of linked TDT
% hardware, and to control the output voltage. Optionally, it is also used
% to obtain measurements from a power meter by an analogue voltage signal.
% If Synapse is not in a run-time mode before measurement begins then it is
% set to Preview for the duration of the measurements before switching back
% to the original mode.
% 
% The Synapse project must at least contain one instance of the LaserTester
% Gizmo. This must feed the digital-to-analogue port that provides input
% for the laser. For automated power measurements, the project has
% additional requirements according to the type of power meter and the mode
% of measurement e.g. a PM100D sends an analogue signal to the TDT hardware
% for averaging and reading via SynapseAPI.
% 
% Input arguments are optional and must all be Name/Value pairs, where a
% named parameter is assigned a given value. In the descriptions below, a
% string refers to a row vector of type char, rather than a MATLAB string
% array. The following is a list of available parameters:
% 
% 'host' - A string naming the host system that is running Synapse. For
%   example, 'ESI-WSIFRI037'. Defaults to 'localhost', assuming that
%   Synapse and Matlab are running on the same system.
% 
% 'lasertester' - Names the specific instance of the LaserTester Gizmo in
%   the current Synapse project. It is this specific LaserTester Gizmo that
%   will be used to provide voltage input to the laser. Default
%   'LaserTester1'.
% 
% 'input' - Takes one of two forms. If a scalar is given, then it must be a
%   non-zero, natural number N. In this case, N voltages will be generated
%   that are evenly spaced in the given range (see parameter 'range'). If
%   N = 1 then the only the upper limit of the range is tested.
%   Alternatively, input may be a vector of Voltage values that can have
%   any desired order and distribution. These values must all be within the
%   given range (param 'range'). Default 50.
% 
% 'range' - Inclusive range of input voltages. Given as a two-element
%   vector with format [ <minimum voltage> , <maximum voltage> ]. Default
%   [ 0 , 5 ].
% 
% 'index' - The LaserTester Gizmo has a control parameter called
%   'Wavelength'. In practice, this is an index with value 0 or 1 that
%   specifies which of two sets of outputs receive non-zero input. Up to
%   two different lasers can be connected to the TDT hardware. The laser
%   that receives non-zero input is then selected using by setting the
%   LaserTester Wavelength number e.g. 0 might indicate a green laser and 1
%   might indicate yellow. The 'index' parameter simply specifies which of
%   the two lasers to use during measurement testing. Default 0.
% 
% 'ttlinvert' - If laser requires digital input control signal then the
%   LaserTester will feed a TTL signal with 0 to block emission and 1 to
%   enable emission, by default (ttlinvert is 0). But the logic
%   can be inverted by setting ttlinvert to 1. In this case, an output
%   signal of 1 blocks emission, and an output of 0 enables emission.
%   Default ttlinvert 0.
%
% 'measurement' - String naming the method of measurement. This defaults to
%   'manual'. Supported modes of measurement include:
%   
%   'manual' - SynapseAPI is used to automatically set the input voltage to
%     the laser. But the power of the output emission must be read by the
%     user and typed in manually when prompted in the command window.
%   
%   'pm100d' - Automatically take measurements from a ThorLabs PM100D power
%     meter. The analogue output port on the PM100D is connected to an
%     analogue-to-digital input port on the TDT hardware. In synapse, this
%     feeds a Signal Accumulator Gizmo to compute the average PM100D output
%     over a set interval. The average is read via SynapseAPI and converted
%     from volts to mW. The process requires the user to take the following
%     actions when prompted. 1) Change the PM100D measurement range. 2)
%     Block or disable then unblock/enable the laser to measure the PM100D
%     output with zero emissions. PM100D output is converted to mW from
%     volts by ( V - V_0 ) / 2.0 * Pmax where V is the measured voltage,
%     V_0 is the voltage with zero emission, 2.0 is the PM100D output
%     voltage at Pmax, and Pmax is the wavelength-corrected upper range
%     currently set in the PM100D. Signal Accumulator Gizmo must be set as
%     follows: PM100D voltage fed to input called 'Input'; General>Control
%     set to 'Strobe Input'; General Tab check boxes enabled 'Compute
%     Average', 'Dynamic Output', Accumulator rate 'Max'; Run-time Options
%     tab check box enabled 'Run-time Interface'; in Gizmo diagram view,
%     put check mark on the API gear symbol next to the output called
%     'Main'.
% 
% Measurement method specific parameters exist for the following methods.
% These all have a prefix of the form <method>_ e.g. pm100d_.
% 
%   'manual' - There are no parameters specific to this method.
%   
%   'pm100d' - The PM100D power meter from ThorLabs can amplify the signal
%     from a connected sensor at several orders of magnitude, corrected for
%     a specific wavelength of light. For automatic measurements to be
%     taken, both the wavelength and the magnitude must be set manually by
%     the user. In order to convert input voltages to the mW equivalent,
%     the procedure requires knowledge about what orders of magnitude are
%     used and also a coefficient that corrects for the wavelength.
% 
%     'pm100d_coefficient' - A scalar number that corrects for the
%       wavelength that is being measured. This can be multiplied by the
%       appropriate order of magnitude to get the upper limit of the
%       measured power at a given range setting on the PM100D. To find
%       this, first select the desired wavelength in the PM100D user
%       interface, then select the range. In the manual range, find the
%       magnitude that measures in the 1.0 mW scale e.g. 4.5 mW for 505nm.
%       Provide that value for this parameter. Default 4.5.
%     
%     'pm100d_magnitudes' - A series of magnitudes of amplification for the
%       PM100D power measurements. These are multiplied into the given
%       coefficient to determine the absolute ranges available. Given as a
%       vector of decimal values. Default [ 0.01 , 0.1 , 1 , 10 , 100 , 
%       1000 ].
%     
%     'pm100d_threshold' - A scalar value in the range (0,1] taken as a
%       fraction of the current range limit of the PM100D measurement
%       range. Once this is exceeded, the user is prompted to increase the
%       measurement range in the PM100D. Default 0.95.
%     
%     'pm100d_signalaccumulator' - Names the Signal Accumulator Gizmo from
%       which the average voltage output of the PM100D is to be read.
%       Default 'AvgPMvolts'.
%     
%     'pm100d_timer' - Scalar value giving the number of seconds that pass
%       before taking a measurement from the Signal Accumulator Gizmo. The
%       Gizmo's Strobe parameter is raised from 0 to 1. A timer runs for
%       the set duration. The measurement is taken. And the Strobe
%       parameter is lowered again. Default 1.0.
% 
% Written by Jackson Smith - October 2022 - Fries Lab (ESI Frankfurt)
% 
  
  %%% Constants %%%

  % Valid measurement method strings
  C.measurements = { 'manual' , 'pm100d' } ;

  % Synapse run-time modestrings
  C.runtimestr = { 'Preview' , 'Record' } ;

  % Default run-time mode
  C.runtimedef = 'Preview' ;

  % Verify Synapse mode this many times, with this duration between checks
  C.modechecks = 25 ;
  C.modepause  = 0.2 ; % in seconds


  %%% Parameters %%%

  % Set default general parameters
  par.host = 'localhost' ;
  par.lasertester = 'LaserTester1' ;
  par.input = 50 ;
  par.range = [ 0 , 5 ] ;
  par.index = 0 ;
  par.ttlinvert = 0 ;
  par.measurement = 'manual' ;

  % Set pm100d specific parameter
  par.pm100d_coefficient = 4.5 ;
  par.pm100d_magnitudes = [ 0.01 , 0.1 , 1 , 10 , 100 , 1000 ] ;
  par.pm100d_threshold = 0.95 ;
  par.pm100d_signalaccumulator = 'AvgPMvolts' ;
  par.pm100d_timer = 1 ;

  % Define functions that test validity of input parameter values. Return
  % true if input is valid.
  val.host = @validstring ;
  val.lasertester = @validstring ;
  val.input = @( x ) validnumbers( x , [ 1 , Inf ] ,  1  ,  true ) || ...
                     validnumbers( x , [ 0 , Inf ] , [ ] , false ) ;
  val.range = @( x ) validnumbers( x , [ 0 , 5.5 ] , 2 ) && ...
                     x( 2 ) > x( 1 ) ;
  val.index = @( x ) validnumbers( x , [ 0 , 1 ] , 1 , true ) ;
  val.ttlinvert = @( x ) validnumbers( x , [ 0 , 1 ] , 1 , true ) ;
  val.measurement = @( s ) validstring( s , C.measurements ) ;

  val.pm100d_coefficient = @( x ) validnumbers( x, [ realmin , Inf ], 1 ) ;
  val.pm100d_magnitudes = @validnumbers ;
  val.pm100d_threshold = @( x ) validnumbers( x , [ 0 , 1 ] , 2 ) ;
  val.pm100d_signalaccumulator = @validstring ;
  val.pm100d_timer = @( x ) validnumbers( x , [ 0 , Inf ] , 1 ) ;


  %%% Input args %%%
  
  % Check number of input/output args
  nargoutchk( 0 , 1 )
  
  % Name/Value pairs imply nargin must be multiple of 2
  if  mod( nargin , 2 )
    error( 'Requires Name/Value input argument pairs i.e. even arg count' )
  end

  % Input arg pairs
  for  i = 1 : 2 : nargin - 1

    % Map Name/Value pair to meaningful variables
    [ Name , Value ] = varargin{ i : i + 1 } ;

    % Parameter name is uknown
    if  ~ isfield( par , Name )

      error( 'Uknown parameter name %s' , Name )
    
    % Validity check on new value
    elseif  ~ val.( Name )( Value )

      error( 'Invalid value for parameter %s' , Name )

    end % param check

    % Assign new value
    par.( Name ) = Value ;

  end % arg pairs


  %%% Initialisation %%%

  % Number of input voltages given
  if  isscalar( par.input )

    % Just one value, return upper range limit
    if  par.input == 1

      par.input = par.range( 2 ) ;

    % Generate evenly spaced values
    else

      par.input = ( 0 : par.input - 1 ) ./ ( par.input - 1 ) .* ...
        diff( par.range ) + par.range( 1 ) ;

    end % make input values

  % All input voltages in range?
  elseif ~ all( par.range( 1 ) <= par.input & par.input <= par.range( 2 ) )

    error( 'Input voltages not in range.' )

  % Guarantee that par.input is a row vector
  elseif  ~ isrow( par.input )

    par.input = reshape( par.input , 1 , numel( par.input ) ) ;

  end % input voltages

  % Initialise output
  in2out.input_V = par.input ;
  in2out.output_mW = zeros( size( par.input ) ) ;

  % Number of measurements
  N = numel( par.input ) ;

  % Define a TTL logic scheme that converts 0 (false) and 1 (true) input to
  % the correct value
  fttl = @( x ) abs( par.ttlinvert - x ) ;

  % Connect to Synapse
  syn = SynapseAPI( par.host ) ;

  % Query current mode name
  try
    init.modestring = syn.getModeStr ;
  catch
    error( 'Failed to connect to Synapse on host %s' , par.host )
  end

  % Get list of Synapse gizmos, add this to constants list
  C.G = syn.getGizmoNames ;

  % Check that LaserTester Gizmo is there
  if  ~ any( strcmp( par.lasertester , C.G ) )
    error( 'Synapse missing LaserTester Gizmo called %s', par.lasertester )
  end

  % Guarantee run-time mode
  if  ~ validstring( init.modestring , C.runtimestr )
    setsynapsemode( C , syn , C.runtimedef )
  end

  % Select measurement method and perform specific initialisation tasks
  switch  par.measurement
    case  'manual' , fmeasure = @fmeasure_manual ;
                     mdat = finit_manual( C , par , syn ) ;
    case  'pm100d' , fmeasure = @fmeasure_pm100d ;
                     mdat = finit_pm100d( C , par , syn ) ;
  end % measure method


  %%% Measure Laser's Input/Output transfer function %%%

  % Input voltage index initialise to first input value
  i = 1 ;

  % Print headers on each column
  fprintf( 'Input(V),Output(mW)\n' ) ;

  % Set LaserTester so that selected laser is enabled
  syn.setParameterValue( par.lasertester , 'Wavelength' , par.index ) ;
  syn.setParameterValue( par.lasertester ,     'Enable' , fttl( 1 ) ) ;

  % Input measurements , fetch current input voltage
  while  i <= N , V = in2out.input_V( i ) ;

    % Set laser's input voltage
    syn.setParameterValue( par.lasertester , 'VoltsSF' , V ) ;

    % Show value being measured
    fprintf( '%.3fV,' , V )

    % Measure output
    [ mW , mdat ] = fmeasure( par , mdat , syn , V ) ;

    % Invalid measurement, repeat
    if  isempty( mW ) , continue , end

    % Store measurement
    in2out.output_mW( i ) = mW ;

    % Increment to next measurement
    i = i + 1 ;

  end % input measurements
  
  
  %%% Done %%%

  % Disable laser
  syn.setParameterValue( par.lasertester , 'VoltsSF' , 0         ) ;
  syn.setParameterValue( par.lasertester ,  'Enable' , fttl( 0 ) ) ;

  % Re-set initial  Synapsemode string, if different
  if  ~ strcmp( init.modestring , syn.getModeStr )
    setsynapsemode( C , syn , init.modestring )
  end

  % Report
  fprintf( '\nDone\n' )


end % LaserInputOutputMeasure


%%% Validity tests %%%

% Make sure that input is a classic string, a char row vector
function  y = validstring( str , set )

  % Basic checks
  y = isrow( str )  &&  ischar( str ) ;

  % Optionally, string must come from given set
  if  nargin > 1
    y = y  &&  any( strcmp( str , set ) ) ;
  end

end % validstring

% Makes sure that input is real, finite, numeric value(s)
function  y = validnumbers( x , lim , nval , int )

  % Basic test
  y = isnumeric( x )  &&  isvector( x )  &&  isreal( x )  &&  ...
    all( isfinite( x ) ) ;

  % Check optional limits
  if  nargin > 1  &&  ~ isempty( lim )
    y = y  &&  all( lim( 1 ) <= x & x <= lim( 2 ) ) ;
  end

  % Check optional number of values
  if  nargin > 2  &&  ~ isempty( nval )
    y = y  &&  numel( x ) == nval ;
  end

  % Check optional integer values
  if  nargin > 3  &&  int
    y = y  &&  all( ~ mod( x , 1 ) ) ;
  end

end % validnumbers


%%% Utilities %%%

% Robustly set Synapse mode string, or time out and throw error
function  setsynapsemode( C , syn , modestr )
  
  % Send request
  syn.setModeStr( modestr )

  % Verify
  for  i = 1 : C.modechecks , pause( C.modepause )

    % Synapse is now in requested mode
    if  strcmp( syn.getModeStr , modestr )

      return

    % Maximum number of checks but all of them failed verification
    elseif  i == C.modechecks

      error( 'Failed to set Synapse into runtime mode %s', modestr )

    end % cases
  end % verify
end % setsynapsemode


% Take a measurement from PM100D via the Signal Accumulator Gizmo
function  avg = pm100d_volts( par , syn )
  
  % Raise Signal Accumulator strobe to start averaging power meter Aout
  syn.setParameterValue( par.pm100d_signalaccumulator , 'Strobe' , 1 ) ;

  % Wait to accumulate average
  pause( par.pm100d_timer ) ;

  % Take PM100 Aout measurement from Signal Accumulator, in Volts
  avg = syn.getParameterValue( par.pm100d_signalaccumulator , 'out_Main' );

  % Finished measurement, lower Signal Accumulator strobe
  syn.setParameterValue( par.pm100d_signalaccumulator , 'Strobe' , 0 ) ;

end % pm100d_volts


%%% Measurement initialisation functions %%%

% All functions have form: finit( C , par , syn )
% Method specific initialisation steps are performed given main function
% constants C, parameters par, and open SynapseAPI object syn.

% Manual method requires no initialisation
function  mdat = finit_manual( ~ , ~ , ~ ) , mdat = [ ] ; end


% PM100D method must check for existance of Signal Accumulator Gizmo that
% averages the meter's analogue output. mdat is a struct that stores which
% magnitude of amplification the PM100D is currently using, and also a zero
% measurement of the PM100D Aout when the laser emission is blocked.
% Optionally, mdat is fourth input argument, in which case the next
% amplification level index is used, instead of starting from 1. If C is
% empty then skips check for Signal Accumulator gizmo.
function  mdat = finit_pm100d( C , par , syn , mdat )
  
  % Check that Signal Accumulator Gizmo is there
  if  ~ isempty( C )  &&  ...
      ~ any( strcmp( par.pm100d_signalaccumulator , C.G ) )
    error( 'Synapse missing Signal Accumulator Gizmo called %s' , ...
      par.pm100d_signalaccumulator )
  end

  % Increment PM100D amp. level index if mdat is fourth input arg
  if  nargin > 3

    mdat.i = mdat.i + 1 ;

  else % Otherwise, initialise to first amp. level

    mdat.i = 1 ;

  end % input arg index

  % PM100D amplification value in mW
  mdat.amp = par.pm100d_coefficient * par.pm100d_magnitudes( mdat.i ) ;

  % Request that user set this amplification range on PM100D. First, 
  % create message to user.
  msg = sprintf( [ 'Please set PM100D Manual range to %.3fmW.\n' , ...
    'Click OK when done.' ] , mdat.amp ) ;

  % Then prompt user to manually set PM100D measurement range.
  waitfor( warndlg( msg ) )

  % Prompt user to block laser emission
  waitfor( warndlg( [ 'Please block laser emission for zero ' , ...
    'measurement.' , newline , 'Click OK when done.' ] ) )
  
  % Take zero measurement
  mdat.V0 = pm100d_volts( par , syn ) ;

  % Prompt user to unblock laser emission
  waitfor( warndlg( [ 'Please un-block laser emission.' , newline , ...
    'Click OK when done.' ] ) )
  
end % finit_pm100d


%%% Measurement methods %%%

% All functions have form: mW = fmeasure( par , mdat , syn , V )
% Returning scalar mW value from laser for given V input to laser. If mW is
% empty [ ] then measurement failed and will be repeated. par is the
% parameter struct in the main function method. mdat is returned by the
% finit function and maintains method-specific information about the
% measurement's state.

% Manually type the power measurement at each voltage input
function  [ mW , mdat ] = fmeasure_manual( ~ , mdat , ~ , ~ )
  
  % Retrieve input from user
  mW = input( '' , 's' ) ;

  % Convert to double floating point value
  mW = str2double( mW ) ;

  % Not a valid numeric input, return empty
  if  ~ validnumbers( mW , [ 0 , Inf ] , 1 ) , mW = [ ] ; end

  % Otherwise, show unit
  fprintf( '\bmW\n' )
  
end % fmeasure_manual


% Semi-automated measurement of laser power output from a PM100D meter
function  [ mW , mdat ] = fmeasure_pm100d( par , mdat , syn , ~ )
  
  % Measure PM100D output in volts
  Vout = pm100d_volts( par , syn ) ;

  % Convert from V to mW
  mW = ( Vout - mdat.V0 ) / 2.0 * mdat.amp ;
  
  % mW output exceeds threshold, go to next amp level and return empty to
  % signal that the input voltage should stay the same
  if  mW > par.pm100d_threshold * mdat.amp

    mdat = finit_pm100d( [ ] , par , syn , mdat ) ;
      mW = [ ] ;

  % Measurement is in range, print the result
  else

    fprintf( '%.3fmW\n' , mW )

  end
  
end % fmeasure_manual

