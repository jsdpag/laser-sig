
classdef  LaserSignal < handle
% 
% LaserSignal uses SynapseAPI to control a specific LaserSignal Gizmo in a
% running session of Synapse. This allows for automated control of the
% output from a connected TDT device for the purpose of driving lasers to
% generate signals with one of two types: 1) -90 deg phase shifted
% sinusoid, 2) a plateau with sinusoidal rising and falling phase at the
% start and finish. In fact, this class is only used for setting
% parameters in the associated Synapse Gizmo. Use DAQ event markers to
% trigger/abort laser emissions.
% 
% NOTE: two lasers can be controlled, each with their own Voltage scaling
% factor and baseline shift. Hence, values can be chosen that drive the two
% lasers in the same range of output power values (e.g. in mW). Then, the
% pre-amp parameter can be treated as the fraction of total output power
% above baseline, for both lasers.
% 
% Written by Jackson Smith - August 2022 - Fries Lab (ESI Frankfurt)
% 
  

  properties ( Constant = true )
    
    % Mandatory list of parameters (i.e. Gizmo controls) that the
    % LaserSignal Gizmo must have.
    REQPAR = { 'DAQON' , 'DAQOFF' , 'Timer' , 'PreAmp' , 'Laser0SF' , ...
      'Laser0Shift' , 'Laser1Shift' , 'Laser1SF' , 'LaserID' , ...
        'Frequency' , 'LatchRfTime' } ;
    
    % Mapping of Gizmo control names to class property names. In register
    % with REQPAR.
    PARMAP = { 'DAQON' , 'DAQOFF' , 'TimerSamp' , 'PreAmp' , 'Laser0SF',...
      'Laser0Shift' , 'Laser1Shift' , 'Laser1SF' , 'LaserID' , ...
        'Frequency' , 'LatchRfTime' } ;
    
    % Maximum allowable Voltage, after scalind + shifting
    MXVOLT = 6 ;
    
  end
  
  
  properties ( AbortSet )
    
    % DAQ marker that signals the start of laser emission
    DAQON  uint16
    
    % DAQ marker that aborts ongoing laser emission. Note that every event
    % marker of value DAQON must be followed by some later marker with
    % value DAQOFF. Only then will a new DAQON marker trigger emission.
    % Otherwise, repeated markers of value DAQON will be ignored.
    DAQOFF  uint16
    
    % Value of a countdown timer, in ms. The timer begins counting down
    % from this value when an event marker with value DAQON is received.
    % NOTE: Upon setting this value, it is automatically rounded up to the
    % end of the final sinusoidal cycle before being rounded up to the next
    % complete TDT sample, at the given TDT sampling rate and sinusoidal
    % frequency.
    % 
    % For example, let Synapse be linked to an RZ2 that samples at
    % 24414.0625Hz, and let the sinusoid have a frequency of 60
    % cycles/second. Timer is assigned a value of 175ms. But 175/1e3*60 =
    % 10.5. That is, 175ms is 10 and one half sinusoidal cycles. Rounding
    % up to 11 full sinusoidal cycles forces Timer to become 11/60*1e3
    % approx. 183.333ms. However, 11/60*24414.0625 is approx. 4475.9 TDT
    % samples. Rounding up to 4476 TDT samples then forces Timer to be
    % 183.33696ms.
    % 
    Timer  double
    
    % Frequency of the sinusoidal waveform, in cycles/second i.e. Hz. Upon
    % setting Frequency, the Timer property is rounded using the same
    % procedure as when the Timer property is directly set.
    Frequency  single
    
    % Pre-amplifier scaling factor. A value in range [0,1]. The raw
    % sinusoidal waveform is scaled/shifted to range [0,1]. Then the pre-
    % amp scaling factor is applied. Afterwards, the conversion to Volts is
    % applied separately for each laser.
    PreAmp  single
    
    % Laser identifier. Specifies with pair of analogue/TTL outputs of the
    % linked LaserSignal Gizmo will generate non-zero output when laser
    % emission is triggered by a DAQON event marker. Values can be 0 or 1,
    % where 0 refers to the laser that receives the first pair of outputs,
    % and 1 refers to the laser that receives the other pair.
    LaserID  uint8
    
    % The laser with ID 0, linked to the corresponding analogue/TTL
    % outputs, will use this scaling factor when converting the pre-amp
    % sinusoid to Voltages.
    Laser0SF  single
    
    % For laser 0. When converting from the pre-amp sinusoid to Volts,
    % first multiply by Laser0SF and then add baseline shift Laser0Shift.
    Laser0Shift  single
    
    % Same as Laser0SF, but for the laser with ID 1 that is fed by the
    % other pair of analogue/TTL LaserSignal Gizmo outputs.
    Laser1SF  single
    
    % Same as Laser0Shift, but for laser 1.
    Laser1Shift  single
    
    % True or false logical value. When false, the analogue output for the
    % selected laser from the LaserSignal Gizmo will contain the scaled and
    % shifted sinusoid. When true, the sinusoid plateaus upon reaching its
    % first peak value, and holds that plateau until the final falling
    % phase of the last sinusoidal cycle. That is, the plateau links the
    % first and last peaks of the sinusoid so that the sinusoidal rising
    % and falling phases are present at the start and end of the laser
    % emission.
    Plateau  logical
    
  end
  
  
  properties  ( Transient )
    
    % Instance of SynapseAPI object
    syn = [ ] ;
    
  end
  
  
  properties  ( SetAccess = private )
    
    % Initialisation flag. Lower when all init is finished.
    init = true ;
    
    % Name of specific LaserSignal Gizmo, a given instance in the Synapse
    % experiment, that this instance of the MATLAB LaserSignal class will
    % uniquely communicate with
    name  char
    
    % Information about the Gizmo
    info  struct
    
    % Gizmo's parent device
    parent  char
    
    % Parent device sampling rate in Hz
    fs  double
    
    % Cell array of char arrays, naming each Gizmo control, or parameter,
    % that is visible to SynapseAPI
    param  cell
    
    % Information about each parameter, this will be a struct. Each field
    % will be named after a parameter in .param, and contain information
    % about that parameter, as returned by SynapseAPI.
    ipar  struct
    
    % Timer value, in number of parent device samples
    TimerSamp  uint32
    
    % Number of parent device samples in the sinusoidal rising phase (which
    % equals num samples in falling phase) just before and after the
    % plateau. When the Plateau property is true then this is equal to half
    % the period of Frequency cycles/second, rounded to the nearest
    % complete sample at fs Hz.
    LatchRfTime  uint32
    
  end
  
  
  methods
    
    function  obj = LaserSignal( syn , nam )
    % 
    % obj = LaserSignal( syn , nam ). Create instance of MATLAB LaserSignal
    % class. syn must be an existing SynapseAPI object handle. nam must be
    % a char row vector i.e. a string naming a LaserSignal Gizmo that is
    % currently visible in Synapse. Returns the new LaserSignal handle.
    % 
      
      %-- Check input --%
      
      % syn is instance of SynapseAPI
      if  ~ ( isa( syn , 'SynapseAPI' ) && isvalid( syn ) )
        
        error( 'syn must be a valid SynapseAPI handle.' )
        
      % nam is a char row vector i.e. a string in the classic sense
      elseif  ~ ( ischar( nam ) && isrow( nam ) )
        
        error( 'nam must be a char row vector i.e. a string' )
        
      end % check input
      
      % All Gizmo names
      names = syn.getGizmoNames ;
      
      % nam is not listed
      if  ~ any( strcmp( nam , names ) )
        
        error( [ '%s is not currently a visible Synapse Gizmo. ' , ...
          'Visible Gizmos include: %s' ] , strjoin( names , ' , ' ) )
        
      end
      
      % Keep handle to SynapseAPI
      obj.syn = syn ;
      
      % Set linked Gizmo name
      obj.name = nam ;
      
      % Check that nam is not linked to any other LaserSignal object
      err = LaserSignal.gizmonames( 'add' , nam ) ;
      
        if  ~ isempty( err ) , error( err ) , end
      
      % Get list of property names from named Gizmo
      obj.param = syn.getParameterNames( nam )' ;
      
      % Are all of the expected Gizmo controls/properties listed?
      if  ~ all( ismember( obj.REQPAR , obj.param ) )
        
        error( 'Gizmo %s lacks controls called: ' , nam , ...
          strjoin( setdiff( obj.REQPAR , obj.param ) , ' , ' ) )
        
      end % lacking one or more Gizmo controls
      
      
      %-- Initialise remaining object parameters --%
      
      % Information about the named Gizmo
      obj.info = syn.getGizmoInfo( nam ) ;
      
      % Gizmo's parent device
      obj.parent = syn.getGizmoParent( nam ) ;
      
      % Parent device sampling rate
      obj.fs = getfield( syn.getSamplingRates , obj.parent ) ;
      
      % Initialise parameter info with field-less struct
      obj.ipar = struct ;
      
      % Gizmo parameter names
      for  P = obj.param , par = P{ 1 } ; 
        
        % Retrieve parameter info
        obj.ipar.( par ) = syn.getParameterInfo( nam , par ) ;
        
        % Find index of param name in list of Gizmo controls
        i = strcmp( par , obj.REQPAR ) ;
        
        % Gizmo control maps to MATLAB object parameter named ...
        map = obj.PARMAP{ i } ;
        
        % Retrieve parameter value
        obj.( map ) = syn.getParameterValue( nam , par ) ;
        
      end % param info
      
      % Deduce value of Plateau. Is LatchRfTime short enough to enable a
      % plateau? There must be some time gap between the sinusoidal rising
      % and falling phase at the start and end of the analogue signal.
      obj.Plateau = obj.LatchRfTime  <  double( obj.TimerSamp ) / 2 ;
      
      % Convert timer from samples to ms
      obj.Timer = double( obj.TimerSamp ) / obj.fs * 1e3 ;
      
      % Initialisation is finished
      obj.init = false ;
      
    end
    
    
    function  delete( obj )
      
      % Remove name of associated Gizmo from the static names list
      LaserSignal.gizmonames( 'rm' , obj.name )
      
    end
    
    
    function  x = chklim( obj , par , x , spv )
    %
    % x = chklim( obj , par , x , spv ). Check whether value x is within
    % the valid range that is required by the obj parameter named par. x is
    % returned without modification if is within the parameter's range.
    % Otherwise, an error is issued. spv is optional. If true then the new
    % parameter value is sent to the corresponding Synapse Gizmo control,
    % following limit checking. spv defaults true. As an added bonus,
    % issues an error if x is not scalar.
    %
      
      % x must be scalar
      if  ~ isscalar( x )
        error( 'New value of %s must be scalar.' , par )
      end
      
      % Default values
      if  nargin < 4 , spv = true ; end
      estr = '' ;
      
      % Range check
      if      x < obj.ipar.( par ).Min , estr = 'below' ; % x is too big
      elseif  x > obj.ipar.( par ).Max , estr = 'above' ; % x too small
      end
      
      % x is out of range
      if  estr , error( 'New value %s %s''s limits.' , estr , par ) ; end
      
      % Change the corresponding Gizmo control value, unless object is
      % still initialising
      if  spv  &&  ~obj.init
        obj.syn.setParameterValue( obj.name , par , x )
      end
      
    end
    
    
    function  obj = set.DAQON( obj , x )
      obj.DAQON = obj.chklim( 'DAQON' , x ) ;
    end
    
    
    function  obj = set.DAQOFF( obj , x )
      obj.DAQOFF = obj.chklim( 'DAQOFF' , x ) ;
    end
    
    
    function  obj = set.Timer( obj , tnew )
    % 
    % First, rounds up to the end of the end of final sinusoidal cycle.
    % Then rounds up to end of next complete TDT sample.
    % 
      
      % Check that x is scalar
      if  ~ isscalar( tnew )
        error( 'New Time value must be scalar.' )
      end
      
      % First convert from milliseconds to seconds
      x = double( tnew ) / 1e3 ;
      
      % Cast sine frequency as double
      freq = double( obj.Frequency ) ;
      
      % Convert from sec to number of sinusoidal cycles at set frequency.
      % And round up so that we only have complete sinusoidal cycles.
      cyc = ceil( x * freq ) ;
      
      % Now convert to number of samples. And again, round up to next
      % complete sample.
      samp = ceil( cyc / freq * obj.fs ) ;
      
      % Finally, assign millisecond value to property
      obj.Timer = samp / obj.fs * 1e3 ;
      
      % And assign timer value in number of samples
      obj.TimerSamp = samp ;
      
    end
    
    
    function  obj = set.TimerSamp( obj , x )
      
      % Get limits from corresponding Gizmo control
      min = obj.ipar.Timer.Min ;
      max = obj.ipar.Timer.Max ;
      
      % X falls out of range
      if  x < min || max < x
        error( 'Timer (samples) exceeds valid range.' )
      end
      
      % Assign value
      obj.TimerSamp = x ;
      
      % But then we update the Timer control in the LaserSignal Gizmo.
      % Becaues that control expects a value in samples.
      if  ~ obj.init
        obj.syn.setParameterValue( obj.name , 'Timer' , obj.TimerSamp )
      end
      
    end
    
    
    function  obj = set.Frequency( obj , x )
      
      % First, check and update frequency value
      obj.Frequency = obj.chklim( 'Frequency' , x ) ;
      
      % Next, compute number of cycles within current timer duration. And
      % round up to next complete cycle.
      cyc = ceil( obj.Timer / 1e3 * obj.Frequency ) ;
      
      % Set new timer value
      if  ~obj.init , obj.Timer = cyc / obj.Frequency * 1e3 ; end
      
    end


    function  obj = set.PreAmp( obj , x )
      obj.PreAmp = obj.chklim( 'PreAmp' , x ) ;
    end
    
    
    function  obj = set.LaserID( obj , x )
      obj.LaserID = obj.chklim( 'LaserID' , x ) ;
    end
    
    
    function  obj = set.Laser0SF( obj , x )
      obj.Laser0SF = obj.chklim( 'Laser0SF' , x ) ;
    end
    
    
    function  obj = set.Laser0Shift( obj , x )
      obj.Laser0Shift = obj.chklim( 'Laser0Shift' , x ) ;
    end
    
    
    function  obj = set.Laser1SF( obj , x )
      obj.Laser1SF = obj.chklim( 'Laser1SF' , x ) ;
    end
    
    
    function  obj = set.Laser1Shift( obj , x )
      obj.Laser1Shift = obj.chklim( 'Laser1Shift' , x ) ;
    end
    
    
    function  obj = set.Plateau( obj , x )
      
      % Check that new value is scalar
      if  ~ isscalar( x )
        error( 'New Plateau value must be scalar.' )
      end
      
      % Set value
      obj.Plateau = x ;
      
      % Initialisation, don't change LatchRfTime
      if  obj.init
        
      % Plateau enabled
      elseif  obj.Plateau
        
        % Compute one half-period of the sinusoid at set frequency, in sec
        hp = 0.5 / obj.Frequency ;
        
        % Convert to number of TDT samples, and round to next full sample
        obj.LatchRfTime = ceil( hp * obj.fs ) ;
        
      % Plateau disabled, the latch rise/fall time equals timer duration.
      % Thus, there is no time period in between the rise and fall phase.
      % Therefore, the sinusoid is never latched.
      else
        
        obj.LatchRfTime = obj.TimerSamp ;
        
      end % eval new LatchRfTime
      
    end
    
    
  end
  
  
  methods ( Static )
    
    function  err = gizmonames( fstr , nam )
    % 
    % err = gizmonames( fstr , nam ). Maintains static data store of all
    % LaserSignal Gizmo names (i.e. naming each individual instance of the
    % LaserSignal Gizmo). When a new instance of the MATLAB LaserSignal
    % class is created, it must be linked to a unique LaserSignal Gizmo
    % instance. To check this, the Gizmo's name is passed to nam and fstr
    % is 'add'. If no MATLAB LaserSignal exists that is linked to a Gizmo
    % with name nam, then nam is added to the store of names and err is
    % empty. However, if nam is already linked to an existing MATLAB
    % LaserSignal, then nam is not added a second time, and err returns an
    % error message. When an existing MATLAB LaserSignal object is deleted,
    % then the linked Gizmo name is passed to nam, while fstr is 'rm'; this
    % causes nam to be deleted from the store of names.
    % 
      
      % The static data, accessible by all instances of the MATLAB
      % LaserSignal class. Contains the names of all linked Synapse
      % LaserSignal Gizmos.
      persistent  giznam
      
      % First use of giznam, guarantee that it is initialised as empty cell
      if  isempty( giznam )  &&  ~ iscell( giznam ) , giznam = { } ; end
      
      % Default error message
      err = '' ;
      
      % Look for given Gizmo name in existing store of names
      i = strcmp( nam , giznam ) ;
      
      % Implement named function
      switch  fstr
        
        % Add new name to store
        case  'add'
          
          % Name already exists, return error message and do nothing else
          if  any( i )
            err = sprintf( [ '%s is already linked to another ' , ...
              'LaserSignal object' ] , nam ) ;
            return
          end
          
          % Add name
          giznam = [ giznam , { nam } ] ;
          
        % Remove given name from store
        case   'rm'
          
          % Delete the name
          giznam( i ) = [ ] ;
          
        % Not a valid function string
        otherwise , error( '%s is not a valid function string' , fstr )
          
      end
    end
    
  end
  
  
end

