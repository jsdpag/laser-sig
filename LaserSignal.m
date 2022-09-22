
classdef  LaserSignal < handle
% 
% LaserSignal uses SynapseAPI to set the values of the Synapse Controls in
% a specific instance of the LaserSignal Gizmo that is running in a live
% session of Synapse. This allows for automated specification of the
% output from a connected TDT device for the purpose of driving lasers. The
% signals can be one of two types: 1) -90 deg phase shifted
% sinusoid, 2) a plateau with sinusoidal rising and falling phase at the
% start and finish. Note that the LaserSignal.m class is only used for
% setting parameters. See the LaserController Gizmo and class to generate
% timing signals that trigger the onset and offset of signals from the
% LaserSignal Gizmo.
% 
% NOTE: two lasers can be controlled, each with their own Voltage scaling
% factor and baseline shift. Hence, values can be chosen that drive the two
% lasers in the same range of output power values (e.g. in mW). Then, the
% pre-amp parameter SetAmp can be used as a single, intuitive way of
% setting the desired amplitude of the laser output, in milliWatts, for
% either laser.
% 
% Written by Jackson Smith - August 2022 - Fries Lab (ESI Frankfurt)
% 
  

  properties ( Constant = true )
    
    % Mandatory list of parameters (i.e. Gizmo controls) that the
    % LaserSignal Gizmo must have.
    REQPAR = { 'Timer' , 'SetAmp' , 'Laser0SF' , 'Laser0Shift' , ...
      'Laser1Shift' , 'Laser1SF' , 'LaserID' , 'Frequency' , ...
        'LatchRfTime' , 'MaxAmp' } ;
    
    % Mapping of Gizmo control names (field) to class property names
    % (value), where these differ
    PARMAP = struct( 'Timer' , 'TimerSamp' ) ;
    
  end
  
  
  properties ( AbortSet )
    
    % Target value of a countdown timer, in ms. This is the value that the
    % timer will aim for. The actual time is dependent on both the
    % sinusoidal frequency and the TDT sampling rate (see below). The timer
    % begins counting down from this value when the Input-1 (LaserON)
    % receives a high value (true, 1).
    % 
    % NOTE: Upon setting this value, it is automatically rounded up to the
    % end of the final sinusoidal cycle before being rounded up to the next
    % complete TDT sample, at the given TDT sampling rate and sinusoidal
    % frequency. The rounded value is stored in the TimerUp property. The
    % original target value will be maintained in Timer so that Timer <=
    % TimerUp. If the sinusoidal frequency is changed then the TimerUp
    % value is recalculated from the value stored in Timer.
    % 
    % For example, let Synapse be linked to an RZ2 that samples at
    % 24414.0625Hz, and let the sinusoid have a frequency of 60
    % cycles/second. Timer is assigned a value of 175ms. But 175/1e3*60 =
    % 10.5. That is, 175ms is 10 and one half sinusoidal cycles. Rounding
    % up to 11 full sinusoidal cycles requires 11/60*1e3 approx. 183.333ms.
    % However, 11/60*24414.0625 is approx. 4475.9 TDT samples. Rounding up
    % to 4476 TDT samples requires 183.33696ms. Hence, Timer = 175ms. But
    % TimerUp = 183.33696. And TimerSamp = 4476. Thus the actual timer will
    % run 8.33696ms longer than the target value.
    % 
    Timer  double
    
    % Frequency of the sinusoidal waveform, in cycles/second i.e. Hz. Upon
    % setting Frequency, the TimerUp property is calculated using the same
    % procedure as when the Timer property is set.
    Frequency  single
    
    % The target amplitude of the laser output, in milliWatts. The raw
    % sinusoidal signal spans [0,1] from peak to trough. This is multiplied
    % by the SetAmp value, then divided by MaxAmp, producing a sinusoid in
    % the range [0,1]. It is interpreted as the fraction of the total
    % output value. The laser-specific scaling and shifting factors are
    % then applied to transform the fraction into a corresponding Voltage
    % value, such that the peak voltage drives the laser at SetAmp. Note!
    % If SetAmp > MaxAmp then the LaserSignal Gizmo will not produce
    % output.
    SetAmp  single
    
    % The maximum power output of the lasers when driven at their maximum
    % input voltage. This should be the maximum measured output as it is
    % when delivered to the target tissue rather than the maximum output of
    % the laser at source.
    MaxAmp  single
    
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
  
  
  properties  ( SetAccess = private , AbortSet )
    
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
    
    % Timer valus, in milliseconds, after rounding up to the next complete
    % sinusoidal cycle and TDT sample.
    TimerUp  double
    
    % Timer value, in number of parent device samples. Equals the same time
    % duration as in TimerUp.
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
      obj.fs = getfield( syn.getSamplingRates , obj.parent ) ; %#ok
      
      % Initialise parameter info with field-less struct
      obj.ipar = struct ;
      
      % Gizmo parameter names
      for  P = obj.param , par = P{ 1 } ; 
        
        % Retrieve parameter info
        obj.ipar.( par ) = syn.getParameterInfo( nam , par ) ;
        
        % Gizmo control maps to MATLAB object parameter named ...
        if  isfield( obj.PARMAP , par )
          map = obj.PARMAP.( par ) ;
        else
          map = par ;
        end
        
        % Retrieve parameter value
        obj.( map ) = syn.getParameterValue( nam , par ) ;
        
      end % param info
      
      % Deduce value of Plateau. Is LatchRfTime short enough to enable a
      % plateau? There must be some time gap between the sinusoidal rising
      % and falling phase at the start and end of the analogue signal.
      obj.Plateau = obj.LatchRfTime  <  double( obj.TimerSamp ) / 2 ;
      
      % Convert timer from samples to ms. Assignment sets TimerUp as well.
      obj.Timer = double( obj.TimerSamp ) / obj.fs * 1e3 ;
      
      % Initialisation is finished
      obj.init = false ;
      
    end
    
    
    function  delete( obj )
      
      % Remove name of associated Gizmo from the static names list
      LaserSignal.gizmonames( 'rm' , obj.name )
      
    end
    
    
    function  x = chklim( obj , par , x )
    %
    % x = chklim( obj , par , x ). Check whether value x is within the
    % valid range that is required by the obj parameter named par. x is
    % returned without modification if is within the parameter's range.
    % Otherwise, an error is issued. As added bonuses, issues an error if
    % x is not scalar, and sets new value to corresponding Gizmo control if
    % the LaserSignal object has finished initialisation.
    %
      
      % x must be scalar
      if  ~ isscalar( x ) , error( '%s must be scalar.' , par ) , end
      
      % Default error string
      estr = '' ;
      
      % Range check
      if      x < obj.ipar.( par ).Min , estr = 'below' ; % x is too big
      elseif  x > obj.ipar.( par ).Max , estr = 'above' ; % x too small
      end
      
      % x is out of range
      if  estr , error( 'New value %s %s''s limits.' , estr , par ) ; end
      
      % Initialising, take no action
      if  obj.init
        
      % Change the corresponding Gizmo control value
      elseif  ~ obj.syn.setParameterValue( obj.name , par , x )
        
        % Failed to update control
        error( 'Failed to update control %s of Gizmo %s.', par, obj.name )
        
      end % change Gizmo control value
      
    end
    
    
    function  set.SetAmp( obj , x )
      
      % Check for scalar value
      if  ~ isscalar( x )
        
        error( 'New SetAmp value must be scalar.' )
        
      % New value must NOT exceed MaxAmp
      elseif  x > obj.MaxAmp
        
        error( 'New SetAmp value is greater than MaxAmp.' )
        
      end % input error check
      
      % Further error checking, and set Gizmo control value
      obj.SetAmp = obj.chklim( 'SetAmp' , x ) ;
      
    end
    
    
    function  set.MaxAmp( obj , x )
      
      % Set Gizmo control
      obj.MaxAmp = obj.chklim( 'MaxAmp' , x ) ;
      
      % New MaxAmp value is less than current SetAmp value, so assign
      % SetAmp to its maximum valid value
      if  obj.MaxAmp < obj.SetAmp , obj.SetAmp = obj.MaxAmp ; end
      
    end
    
    
    function  set.Timer( obj , x )
    %
    % Assign new target duration for the timer, in milliseconds
    %
      
      % Check that x is scalar
      if  ~isscalar( x ) , error( 'New Time value must be scalar.' ) , end
      
      % Assign new target timer duration
      obj.Timer = x ;
      
      % Round up to next complete sinusoidal cycle and TDT sample
      obj.TimerUp = obj.Timer ;
      
    end
    
    
    function  set.TimerUp( obj , x )
    % 
    % First, rounds up to the end of the end of final sinusoidal cycle.
    % Then rounds up to end of next complete TDT sample.
    %   
      
      % Simple assignment during initialisation
      if  obj.init , obj.TimerUp = x ; return , end
      
      % Cast sine frequency as double
      freq = double( obj.Frequency ) ;
      
      % Convert from ms to number of sinusoidal cycles at set frequency.
      % And round up so that we only have complete sinusoidal cycles.
      cyc = ceil( x / 1e3 * freq ) ;
      
      % Now convert to number of samples. And again, round up to next
      % complete sample.
      samp = ceil( cyc / freq * obj.fs ) ;
      
      % Convert from TDT samples to milliseconds and assign rounded timer
      % duration to TimerUp
      obj.TimerUp = samp / obj.fs * 1e3 ;
      
      % And assign new timer value in number of TDT samples
      obj.TimerSamp = samp ;
      
    end
    
    
    function  set.TimerSamp( obj , x )
      
      % Assign value. Input arg string refers to the Gizmo control.
      obj.TimerSamp = obj.chklim( 'Timer' , x ) ;
      
      % Re-calculate latch time
      obj.implementplateau
      
    end
    
    
    function  set.Frequency( obj , newfreq )
      
      % Initialisation phase, set value and quit
      if  obj.init , obj.Frequency = newfreq ; return , end
      
      % Check and assign new frequency value
      obj.Frequency = obj.chklim( 'Frequency' , newfreq ) ;
      
      % Re-calculate timer extension to target value
      obj.TimerUp = obj.Timer ;
      
    end
    
    
    function  set.LatchRfTime( obj , x )
      obj.LatchRfTime = obj.chklim( 'LatchRfTime' , x ) ;
    end
    
    
    function  set.LaserID( obj , x )
      obj.LaserID = obj.chklim( 'LaserID' , x ) ;
    end
    
    
    function  set.Laser0SF( obj , x )
      obj.Laser0SF = obj.chklim( 'Laser0SF' , x ) ;
    end
    
    
    function  set.Laser0Shift( obj , x )
      obj.Laser0Shift = obj.chklim( 'Laser0Shift' , x ) ;
    end
    
    
    function  set.Laser1SF( obj , x )
      obj.Laser1SF = obj.chklim( 'Laser1SF' , x ) ;
    end
    
    
    function  set.Laser1Shift( obj , x )
      obj.Laser1Shift = obj.chklim( 'Laser1Shift' , x ) ;
    end
    
    
    function  set.Plateau( obj , x )
      
      % Check that new value is scalar
      if  ~ isscalar( x )
        error( 'New Plateau value must be scalar.' )
      end
      
      % Set value
      obj.Plateau = x ;
      
      % Update LatchRfTime appropriately
      obj.implementplateau
      
    end
    
    
    function  implementplateau( obj )
    % 
    % implementplateau( obj ). Does the job of actually setting the
    % LatchRfTime property/Gizmo control to the value required to implement
    % the state of the Plateau property.
    % 
      
      % Initialisation , no action
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

