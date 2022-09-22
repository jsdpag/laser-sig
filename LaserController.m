
classdef  LaserController < handle
% 
% LaserController uses SynapseAPI to set the Synapse Control values of a
% specific instance of a LaserController Gizmo that is running in a live
% session of Synapse.
% 
% The LaserController Gizmo is intended to control the joint timing of the
% LaserSignal Gizmo and event-triggered buffering Gizmos. It can initiate
% both processes based on an incoming 16-bit event code. Optionally, it can
% also wait for a visual photodiode trace to cross a threshold. Hence, the
% timing of the laser emission and the buffering can be triggered at an
% arbitrary time, or locked to a visual event on the stimulus monitor.
% 
% The photodiode signal must cross a set threshold in a specific direction
% (rising or falling through). In addition, all further threshold crossings
% will be ignored for a set duration, to filter out possible noise.
% 
% A delay can be imposed upon the onset of the laser emission. This might
% be needed to simulate the visual latency of the target site when
% triggering the laser and buffer with a visual event. However, the
% buffering trigger will always occur as soon as the necessary event marker
% and photodiode conditions are satisfied.
% 
% Optionally, the laser onset event markers can be ignored in favour of a
% manual trigger button presented by Synapse.
% 
% A liberal laser de-activation signal is triggered in response to one of
% three possible events. Two event marker codes can be tested for. One can
% be a late but guaranteed event e.g. end of trial. The second can be an
% early but optional event e.g. behavioural response. The third
% possibility is the release of the manual trigger button.
% 
% Written by Jackson Smith - September 2022 - Fries Lab (ESI Frankfurt)
% 
  

  properties ( Constant = true )
    
    % Mandatory list of parameters (i.e. Gizmo controls) that the
    % LaserController Gizmo must have.
    REQPAR = { 'EventIntOn' , 'EventIntReset' , 'LaserDelay' , ...
      'UseLaser' , 'UsePhotodiode' , 'PhotodiodeThreshold' , ...
        'PhotodiodeDirection' , 'PhotodiodeTimeLow' , 'Enablemanual' , ...
          'Trigger' , 'EventIntRstOpt' } ;
    
  end
  
  
  properties ( AbortSet )
    
    % Event marker integer codes that trigger the onset (EventIntOn) or
    % offset (EventIntR*) of the laser signals.
    EventIntOn  uint16
    EventIntReset  uint16
    EventIntRstOpt  uint16
    
    % Once laser/buffer onset is triggered, the laser signal can be delayed
    % by approximately this many milliseconds.
    LaserDelay  single
    
    % Binary switch controls whether or not the laser signal is actually
    % triggered. Mainly a safety feature.
    UseLaser  uint8
    
    % Binary switch. If true/high then the laser/buffer onset trigger is
    % sent after 1) the EventIntOn event marker is received, and then 2)
    % the photodiode signal crosses a value of PhotodiodeThreshold in the
    % given direction (PhotodiodeDirection).
    UsePhotodiode  uint8
    
    % Photodiode event threshold.
    PhotodiodeThreshold  single
    
    % Direction of required threshold crossing. 0: falling, 1: rising.
    PhotodiodeDirection  uint8
    
    % Photodiode direction string, for user convenience
    PhotodiodeDirectionStr  char
    
    % Once photodiode signal crosses threshold in required direction, all
    % other such crossings are ignored for this amount of time, in
    % milliseconds.
    PhotodiodeTimeLow  single
    
    % Binary switch. If off/low/false then the event marker/photodiode
    % signals are used to trigger laser signal onset. Otherwise, the manual
    % trigger button is used. Event markers can still shut the laser signal
    % off, no matter what this parameter is.
    Enablemanual  uint8
    
    % The manual trigger button. Returns true when pressed and false when
    % not.
    Trigger  uint8
    
  end
  
  
  properties  ( Transient )
    
    % Instance of SynapseAPI object
    syn = [ ] ;
    
  end
  
  
  properties  ( SetAccess = private , AbortSet )
    
    % Initialisation flag. Lower when all init is finished.
    init = true ;
    
    % Name of specific LaserController Gizmo, a given instance in the
    % Synapse experiment, that this instance of the MATLAB LaserController
    % class will uniquely communicate with
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
    
  end
  
  
  methods
    
    function  obj = LaserController( syn , nam )
    % 
    % obj = LaserController( syn , nam ). Create instance of MATLAB
    % LaserController class. syn must be an existing SynapseAPI object
    % handle. nam must be a char row vector i.e. a string naming a
    % LaserController Gizmo that is currently visible in Synapse. Returns
    % the new LaserController handle.
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
      
      % Check that nam is not linked to any other LaserController object
      err = LaserController.gizmonames( 'add' , nam ) ;
      
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
        
        % Retrieve parameter value
        obj.( par ) = syn.getParameterValue( nam , par ) ;
        
      end % param info
      
      % Initialisation is now complete, any new assignment to object
      % parameters will be transmitted to Gizmo control vlaues
      obj.init = false ;
      
    end
    
    
    function  delete( obj )
      
      % Remove name of associated Gizmo from the static names list
      LaserController.gizmonames( 'rm' , obj.name )
      
    end
    
    
    function  x = chklim( obj , par , x )
    %
    % x = chklim( obj , par , x ). Check whether value x is within the
    % valid range that is required by the obj parameter named par. x is
    % returned without modification if is within the parameter's range.
    % Otherwise, an error is issued. As an added bonus, issues an error if
    % x is not scalar.
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
    
    
    function  set.EventIntOn( obj , x )
      obj.EventIntOn = obj.chklim( 'EventIntOn' , x ) ;
    end
    
    
    function  set.EventIntReset( obj , x )
      obj.EventIntReset = obj.chklim( 'EventIntReset' , x ) ;
    end
    
    
    function  set.EventIntRstOpt( obj , x )
      obj.EventIntRstOpt = obj.chklim( 'EventIntRstOpt' , x ) ;
    end
    
    
    function  set.LaserDelay( obj , x )
      obj.LaserDelay = obj.chklim( 'LaserDelay' , x ) ;
    end
    
    
    function  set.UseLaser( obj , x )
      obj.UseLaser = obj.chklim( 'UseLaser' , x ) ;
    end
    
    
    function  set.UsePhotodiode( obj , x )
      obj.UsePhotodiode = obj.chklim( 'UsePhotodiode' , x ) ;
    end
    
    
    function  set.PhotodiodeThreshold( obj , x )
      obj.PhotodiodeThreshold = obj.chklim( 'PhotodiodeThreshold' , x ) ;
    end
    
    
    function  set.PhotodiodeDirection( obj , x )
      
      % Check new value and transmit to Synapse
      obj.PhotodiodeDirection = obj.chklim( 'PhotodiodeDirection' , x ) ;
      
      % Re-set the corresponding string
      switch  obj.PhotodiodeDirection
        case  false , obj.PhotodiodeDirectionStr = 'falling' ;
        case   true , obj.PhotodiodeDirectionStr =  'rising' ;
      end
      
    end
    
    
    function  set.PhotodiodeDirectionStr( obj , x )
      
      % Make sure that new value is a valid string
      if  ~ any( strcmp( x , { 'falling' , 'rising' } ) )
        error( 'Invalid string. Must be ''falling'' or ''rising''.' )
      end
      
      % Store new string
      obj.PhotodiodeDirectionStr = x ;
      
      % Set corresponding logical value
      switch  obj.PhotodiodeDirectionStr
        case  'falling' , obj.PhotodiodeDirection = false ;
        case   'rising' , obj.PhotodiodeDirection =  true ;
      end
      
    end
    
    
    function  set.PhotodiodeTimeLow( obj , x )
      obj.PhotodiodeTimeLow = obj.chklim( 'PhotodiodeTimeLow' , x ) ;
    end
    
    
    function  set.Enablemanual( obj , x )
      obj.Enablemanual = obj.chklim( 'Enablemanual' , x ) ;
    end
    
    
    function  set.Trigger( obj , x )
      obj.Trigger = obj.chklim( 'Trigger' , x ) ;
    end
    
  end
  
  
  methods ( Static )
    
    function  err = gizmonames( fstr , nam )
    % 
    % err = gizmonames( fstr , nam ). Maintains static data store of all
    % LaserController Gizmo names (i.e. naming each individual instance of
    % the LaserController Gizmo). When a new instance of the MATLAB
    % LaserController class is created, it must be linked to a unique
    % LaserController Gizmo instance. To check this, the Gizmo's name is
    % passed to nam and fstr is 'add'. If no MATLAB LaserController exists
    % that is linked to a Gizmo with name nam, then nam is added to the
    % store of names and err is empty. However, if nam is already linked to
    % an existing MATLAB LaserController, then nam is not added a second
    % time, and err returns an error message. When an existing MATLAB
    % LaserController object is deleted, then the linked Gizmo name is
    % passed to nam, while fstr is 'rm'; this causes nam to be deleted from
    % the store of names.
    % 
      
      % The static data, accessible by all instances of the MATLAB
      % LaserController class. Contains the names of all linked Synapse
      % LaserController Gizmos.
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
              'LaserController object' ] , nam ) ;
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

