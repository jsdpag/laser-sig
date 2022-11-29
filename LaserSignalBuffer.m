
classdef  LaserSignalBuffer < handle
% 
% LaserSignalBuffer uses SynapseAPI to set the values of the Synapse
% Controls in a specific instance of the LaserSignalBuffer Gizmo that is
% running in a live session of Synapse.
%
% Together, these permit arbitrary signals to be created in Matlab and then
% transferred, by the LaserSignalBuffer.m object, to a TDT memory buffer
% that is maintained by the LaserSignalBuffer.rcx Gizmo for triggered
% playback. The MATLAB object mediates this transfer.
% 
% Because SynapseAPI uses the JSON data format to transfer values, the
% transfer speed is very slow. Therefore, signals are compressed for
% transfer and then decompressed by the Gizmo. Thus, the maximum resolution
% of the output signal is 16-bit.
% 
% To load a signal, assign a double numeric array to the .Signal property.
% An error is raised if the size of the compressed signal exceeds the
% capacity of the Gizmo's memory buffer. The maximum raw, uncompressed
% signal length in samples can be checked in the .MaxLength property.
% 
% The sampling rate of the LaserSignalBuffer Gizmo can be set with the
% .FsTarget property. Note that this is an approximation, at best, which
% is constrained by the clock rate of the Gizmo's parent device. The actual
% sampling rate is provided in .FsSignal. The duration of the loaded signal
% at the actual sampling rate, in seconds, is given by .TimerSec.
% 
% Written by Jackson Smith - August 2022 - Fries Lab (ESI Frankfurt)
% 
  

  properties ( Constant = true )
    
    % Mandatory list of parameters (i.e. Gizmo controls) that the
    % LaserSignal Gizmo must have.
    REQPAR = { 'Signal' , 'Timer' , 'TickPerSamp' , 'Scale' } ;
    
  end
  
  
  properties ( AbortSet )
    
    % Row vector containing the raw, uncompressed signal that has been
    % loaded into the Gizmo's buffer.
    Signal  double

    % This is the signal output sampling rate that we will aim for. But it
    % will be constrained by the rate of the clock in the parent device of
    % the Gizmo.
    FsTarget  double
    
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
    FsClock  double
    
    % Cell array of char arrays, naming each Gizmo control, or parameter,
    % that is visible to SynapseAPI
    param  cell
    
    % Information about each parameter, this will be a struct. Each field
    % will be named after a parameter in .param, and contain information
    % about that parameter, as returned by SynapseAPI.
    ipar  struct

    % Duration of the signal in ticks of the Gizmo's parent device clock.
    % The signal stops playing out once this timer expires.
    Timer  int32
    
    % Parent device clock ticks per sample of output. In effect, the
    % sampling rate of the output.
    TickPerSamp  int32

    % Multiplicative scaling factor that is applied to the signal before
    % compression into pairs of int16 packed into 32-bit words.
    Scale  double

    % Maximum number of samples that the output signal may contain. Compute
    % as 2*BufferSize - 2. We subtract 2 because the first two buffered
    % values are contained in the first 32-bit word. And we just set this
    % to zero.
    MaxLength  double

    % The actual sampling rate of the output signal, once the master
    % clock's rate is factored in.
    FsSignal  double

    % Duration of the signal in number of seconds 
    TimerSec  double
    
  end
  
  
  methods
    
    function  obj = LaserSignalBuffer( syn , nam )
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
      err = LaserSignalBuffer.gizmonames( 'add' , nam ) ;
      
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
      obj.FsClock = getfield( syn.getSamplingRates , obj.parent ) ;
      
      % Initialise parameter info with field-less struct
      obj.ipar = struct ;
      
      % Gizmo parameter names
      for  P = obj.param , par = P{ 1 } ; 
        
        % Retrieve parameter info
        obj.ipar.( par ) = syn.getParameterInfo( nam , par ) ;
        
        % Retrieve parameter value(s)
        switch  par

          % Read contents of buffer as row vector. This requires a
          % decompression.
          case  'Signal'
            W = int32( syn.getParameterValues( nam , 'Signal' )' ) ;

          % Scalar parameters
          otherwise
            obj.( par ) = syn.getParameterValue( nam , par ) ;

        end % get param values
        
      end % param info

      % Before setting obj.Signal, we need the maximum signal length.
      obj.MaxLength = 2 * obj.ipar.Signal.Array  -  2 ;

      % Word indeces. Exclude first word because we will set this
      % permanently to zero. Fetch words up to the end of the timer.
      i = 2 : ceil( obj.Timer / obj.TickPerSamp / 2 ) ;

      % Decompress local copy of Gizmo's buffer contents. Exclude value at
      % buffer index position 0, because of the next step.
      obj.Signal = double( typecast( W( 2 : end ) , 'int16' ) )  /  ...
        obj.Scale ;

      % Guarantee that the buffer contains a zero at index position 0. This
      % way, the buffer component always outputs zeros whenever the laser
      % is supposed to be off.
      syn.setParameterValues( nam , 'Signal' , 0 , 0 ) ;
      
      % Determine the output signal's sampling rate. By assigning this to
      % FsTarget, we automatically populate .FsSignal. Note, FsClock is
      % ticks/second x samples/tick = samples/second
      obj.FsTarget = obj.FsClock / obj.TickPerSamp ;
      
    end
    
    
    function  delete( obj )
      
      % Remove name of associated Gizmo from the static names list
      LaserSignalBuffer.gizmonames( 'rm' , obj.name )
      
    end
    
    
    function  x = setgizmoparam( obj , par , x )
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
    
    
    function  set.Timer( obj , x )
    % Assign new target duration for the timer, in ticks of the master
    % clock.

      obj.Timer = obj.setgizmoparam( 'Timer' , x ) ;
    
    end


    function  set.TickPerSamp( obj , x )
    %
    % Assign new output signal sampling rate by setting the number of
    % parent device clock ticks for each output sample value.
    %
      
      obj.TickPerSamp = obj.setgizmoparam( 'TickPerSamp' , x ) ;
      
    end


    function  set.FsTarget( obj , x )

      % First, see how many complete ticks of the master clock occur within
      % one full sample at the target rate.
      obj.TickPerSamp = floor( obj.FsClock  /  x  ) ;

      % Now we find the real sample rate
      obj.FsSignal = obj.FsClock / obj.TickPerSamp ;

      % Update duration of the signal
      obj.TimerSec = numel( obj.Signal )  /  obj.FsSignal ;

    end


    function  set.Signal( obj , newsig )

      % New signal must be a vector that does not overflow the buffer
      if  numel( newsig ) > obj.MaxLength  ||  ~ isvector( newsig )
        error( 'Signal must be vector with length <= %d.' , obj.MaxLength )
      end

      % Store new signal
      obj.Signal = newsig ;

      % Initialisation, we just read the signal buffer so do nothing else.
      if  obj.init , return , end

      % Scale, cast as int16, and pack into 32-bit words
      W = typecast( int16( obj.Scale * newsig ) , 'int32' ) ;

      % Transfer signal to Gizmo buffer. Do not write over leading zero at
      % index 0 of buffer.
      if  ~ obj.syn.setParameterValue( obj.name , 'Signal' , W , 1 )
        error( 'Failed to write to Signal of %s' , obj.name )
      end

      % Update duration of the signal
      obj.TimerSec = numel( newsig )  /  obj.FsSignal ;

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

