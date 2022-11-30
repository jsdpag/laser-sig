
function  makelasertable( varargin )
% 
% makelasertable wlen0 [wlen1] [wlen2] ...
% 
% Helper function that partially automates the process of measuring and
% estimating the transfer function for a set of lasers. The results are
% written to ASCII CSV files that can readily be imported for use into e.g.
% an ARCADE task for setting laser parameters using the laser-signals
% library.
%
% Input arguments must be classic strings (char row vectors), which is the
% case if the function is invoked in the style of a system command line.
% 
%   e.g. >> makelasertable 505 633
%
% Each argument refers to a separate laser. The position of the argument is
% counted from left to right starting with 0, and incrementing once per
% argument. Hence, the exmaple above has arguments that occupy positions 0
% and 1. The argument's position is taken as the laser's index in the
% LaserTester Gizmo that will be used to control the input voltage, and
% tells the Gizmo which set of outputs to use; each set being linked to a
% separate laser.
% 
% The argument itself must name the wavelength of the laser, in nanometres
% (nm). Again, the example above shows that lasers 0 and 1 have wavelengths
% of 505nm and 633nm.
% 
% It is possible to define a name separately for each laser by providing
% input arguments of the form <wavelength>_<name>. In this case, the
% underscore character '_' separates the numeric wavelength on the left
% from the laser's name, on the right. The name must contain only
% alphanumeric characters and underscores with no whitespace; the first
% character must be alphabetical, so that the name can also function as a
% MATLAB variable name or struct field name.
%
%   e.g. >> makelasertable 505_green 633_red
% 
% The user is prompted to set up the measurement for each laser, according
% to its wavelength and the specified measurement method. Once the transfer
% functions have all been empirically measured, they are fit using the
% transcoef( ) function to find the best-fitting coefficients for the
% transfer( ) function.
% 
% The laser index (arg position), wavelength, and best-fitting coefficients
% are written to a CSV table. Separately, the empirical input to output
% measurements are also written in another CSV table.
% 
% Parameters that control this sequence are set in the makelasertable.csv
% file that exists in the same directory as the makelasertable.m file. Each
% line specifies a separate parameter with the format <name>,<value>.
% 
% tabledir, coefftable, and powertable name the parent directory,
% coefficient table file name, and empirical measurement file name,
% respectively. Do not include file type suffixes e.g. '.csv'. These are
% added automatically.
% 
% All other parameters are Name/Value input argument pairs that are defined
% by LaserInputOutputMeasure (see help for that function). The exception
% are parameters with names following the format pm100d_coef_<wave>nm in
% which <wave> is a given integer wavelength. Collectively, these
% parameters become a lookup table that makelasertable uses to find the
% correct value of the LaserInputOutputMeasure's pm100d_coefficient
% parameter.
% 
% Another exception is 'chans'. By default, this should be 1. It is used
% when the laser light is split as evenly as possible between multiple
% output channels. In this case, chans should be the number of output
% channels. A separate measurement is taken for each channel, per laser.
% When fitting the transfer function, data from all the output channels are
% used. Thus, the transfer function becomes a mapping between voltage in to
% the laser and the expected emisison power from from a single output
% channel. The empirical input/output measurements are stored separately
% per output channel. Output channels are numbered in the same manner as
% laser positions; starting with 0 and incrementing by +1 per channel.
% 
% Written by Jackson Smith - November 2022 - Fries Lab (ESI Frankfurt)
% 
  
  
  %%% Parameters %%%
  
  % Parameter file name and directory
  parnam = 'makelasertable.csv' ;
  pardir = fileparts( which( 'makelasertable' ) ) ;
  
  % Read in parameter file as char row vector
  par = fileread( fullfile( pardir , parnam ) ) ;

  % Separate by newline and comma delimiter characters
  par = strsplit( par , { '\n' , ',' } ) ;

  % Remove any whitespace residue that might appear e.g. Windows reasons
  par = strip( par ) ;

  % Reconfigure into 2 x num-pars cell array of classic strings
  par = reshape( par , 2 , [ ] ) ;

  % Convert into struct, fields name parameters and contain their values
  par = struct( par{ : } ) ;

  % List of constant name/value input args for LaserInputOutputMeasure
  CARGIN = { 'host' , par.host , 'lasertester' , par.lasertester , ...
    'input' , str2double( par.input ) , 'range' , str2num( par.range ) ,...
      'zero' , str2double( par.zero ) , 'measurement' , par.measurement } ;

  % Save for figures
  par.range = CARGIN{ 8 } ;

  % Cast number of output channels from string to double
  par.chans = str2double( par.chans ) ;

    % Basic checks
    if  ~ ( isscalar( par.chans ) && isfinite( par.chans ) && ...
            mod( par.chans , 1 ) == 0 && par.chans > 0 )
      error( [ 'Number of output channels (chans in ' , ...
      'makelasertable.csv) must be scalar, finite integer of 1 or more' ] )
    end

  % Method specific constant input args
  switch  par.measurement

    % Semi-automated measurement using ThorLabs PM100D. Get duration of
    % timer and starting amplification magnitude.
    case  'pm100d' , CARGIN = [ CARGIN , ...
      { 'pm100d_initmagnitude' , str2double( par.pm100d_initmagnitude ) ...
                'pm100d_timer' , str2double( par.pm100d_timer ) } ] ;

    % Method named in makelasertable.csv not currently supported
    otherwise , error( 'Method %s not supported by makelasertable.' )

  end % method specific args

  
  %%% Input arg check %%%

  % Number of input arguments i.e. number of lasers to be measured
  N = nargin ;

  % No input
  if  N == 0
    disp( 'Usage: makelasertable wlen0 [wlen1] [wlen2] ...' )
  end
  
  % Allocate laser wavelengths, names, positions, and output channels. One
  % column per laser. One row per output channel.
  wlen = zeros( par.chans , N ) ;
  name = repmat( { '' } , par.chans , N ) ;
  ipos = repmat( 0 : N - 1 , par.chans , 1 ) ;
  chan = repmat( ( 0 : par.chans - 1 )' , 1 , N ) ;

  % Input args
  for  i = 1 : N

    % Check if arg is char row vector
    if  ~( ischar( varargin{ i } ) && isrow( varargin{ i } ) )
      error( 'Input arg %d is not classic string (char row vector)' , i )
    end
    
    % Parse wavelength and name from input arg
    sarg = regexp( varargin{ i } , '^(?<wlen>\d+)(?<wnam>_\w*)?$' , ...
      'names' ) ;

      % Drop underscore from <wavelength>_<name> formatting
      sarg.wnam( 1 ) = [ ] ;

    % No valid format to input arg
    if  isempty( sarg )
      error( 'Invalid format of arg %d: %s' , i , varargin{ i } )
    end

    % Convert to double floating point
    wlen( : , i ) = str2double( sarg.wlen ) ;

    % Get name
    name( : , i ) = { sarg.wnam } ;

    % Empty name, initialise default with wavelength and laser position
    if  isempty( name{ 1 , i } )
      name( : , i ) = { sprintf( '%d_%d' , wlen( i ) , ipos( i ) ) } ;
    end

  end % input args
  
  % Only real-valued numbers allowed
  if  ~ isreal( wlen )
    error( 'All input strings must be real-valued (not imaginary).' )
  end

  % Only finite values allowed, no Inf or NaN
  if  ~ all( isfinite( wlen ) )
    error( 'All input numbers must be finite, no Inf or NaN.' )
  end

  % Only positive integers are allowed
  if  ~ all( wlen > 0  &  ~ mod( wlen , 1 ) )
    error( 'All input number must be positive integers.' )
  end

  % Make sure that all names are unique ...
  if  ~ isequal( name( 1 , : ) , unique( name( 1 , : ) , 'stable' ) )

    error( 'Laser names must be unique to each laser.' )

  % ... and that they are all valid MATLAB variable/field names
  elseif  ~ all( cellfun( @isvarname , name( 1 , : ) ) )

    error( 'Laser names must be valid MATLAB variable/field names.' )

  end % check laser names


  %%% Method-specific param check %%%

  switch  par.measurement

    % Make sure that all wavelengths have an entry in the PM100D
    % coefficient lookup table
    case  'pm100d'

      % Make all possible lookup table parameter names
      pnam = arrayfun( @( w ) sprintf( 'pm100d_coef_%dnm' , w ) , ...
        wlen( 1 , : ) , 'UniformOutput' , false ) ;

      % Missing wavelength coefficient
      i = ~ isfield( par , pnam ) ;

      % Report missing wavelength coefficients
      if  any( i )
        error( [ 'makelasertable.csv missing pm100d_coef_*nm entry ' , ...
          'for wavelengths: %s' ] , strjoin( varargin( i ) , ' , ' ) )
      end

  end % measurement specific


  %%% Measure transfer functions %%%

  % Allocate cell array, one cell per laser/output channel. One column
  % per laser, one row per output channel.
  in2out = cell( par.chans , N ) ;

  % Lasers, i is the linear index of wlen, name, ipos, chan, & in2out.
  % Progressing in column major order i.e. traverse channels per laser.
  for  i = 1 : par.chans * N

    % Gather together variable name/value args for LaserInputOutputMeasure

    % Method specific args
    switch  par.measurement

      % Semi-automated measurement using ThorLabs PM100D.
      case  'pm100d'

        % Determine wavelength coefficient field name.
        pnam = sprintf( 'pm100d_coef_%dnm' , wlen( i ) ) ;
        vargin = { 'pm100d_coefficient' , str2double( par.( pnam ) ) } ;

    end % method specific args

    % Format user prompt
    prompt = sprintf( ...
      [ 'Please prepare to measure laser %d, %dnm, chan %d, %s power.' ,...
        '\nClick OK when done.' ] , ...
          ipos( i ) , wlen( i ) , chan( i ) , name{ i } ) ;

    % Prompt user to set the measurement device for this laser's wavelength
    waitfor( warndlg( prompt ) )

    % Measure this laser's transfer function
    in2out{ i } = LaserInputOutputMeasure( 'index' , ipos( i ) , ...
      CARGIN{ : } , vargin{ : } ) ;

  end % lasers


  %%% Find best-fitting transfer function coefficients %%%

  % Get one copy of tested input voltages
  volts = in2out{ 1 }.input_V ;

  % Check that the same voltages were tested across lasers
  if  ~ all( cellfun( @( c ) isequal( volts , c.input_V ) , in2out( : ) ) )
    error( 'Voltage input mismatch across measured lasers.' )
  end

  % For fitting procedure, repeat tested voltages per channel
  V = repmat( volts , 1 , par.chans ) ;

  % Eliminate one level of nesting by fetching power output measurements.
  % Continue to store these in the chans x lasers cell array
  mW = cellfun( @( c ) c.output_mW , in2out , 'UniformOutput' , false ) ;

  % Allocate coefficients for each laser. Rows index lasers. Cols ind coef.
  C = zeros( N , 5 ) ;

  % Brute force nonlinear solution, find the forward and inverse piecewise
  % polynomials for spline interpolation
  pp = repmat( struct( 'fwd' , [ ] , 'inv' , [ ] ) , N , 1 ) ;

    % Data for spline fits. We take just one copy of Voltages.
    x = volts ;
    

  % Lasers
  for  i = 1 : N

    % Best-fitting coefficients for each laser
    C( i , : ) = transcoef( V , [ mW{ : , i } ] ) ;

    % Average powers across multiple channels.
    y = mean( cat( 1 , mW{ : , i } ) , 1 ) ;

    % Forward and inverse splines
    pp( i ).fwd = spline( x , y ) ;
    pp( i ).inv = spline( y , x ) ;

  end % lasers


  %%% Write output tables %%%

  % Re-arrange power measurements into an array with one column per input
  % voltage, and one row per channel/laser combination
  mW = reshape( [ mW{ : } ] , numel( volts ) , par.chans * N )' ;

  % Allocate cell array for coefficients table, one row per laser and one
  % more for the header
  txt.coef = cell( 1 , N + 1 ) ;

  % Define header
  txt.coef{ 1 } = [ 'index,nm,name,B,M,V0,P,Vt' , newline ] ;

  % Build formatting string for each line of data
  fmt = [ '%d,%d,%s' , repmat( ',%.9f' , 1 , size( C , 2 ) ) , '\n' ] ;

  % Lasers
  for  i = 1 : N
    txt.coef{ i + 1 } = ...
      sprintf( fmt , ipos( i ) , wlen( i ) , name{ i } , C( i , : ) ) ;
  end

  % Concatenate into string with newlines
  txt.coef = [ txt.coef{ : } ] ;

  % Now allocate for the measured transfer functions
  txt.meas = cell( 1 , 2 ) ;

  % Column headers, identifying each laser for each power column
  txt.meas{ 1 } = [ { 'Volts' } , ...
    arrayfun( @( i , nm , ch , nam ) sprintf( 'Laser%d_%dnm_ch%d_%s', ...
      i, nm, ch, nam{ 1 } ) , ipos(:) , wlen(:) , chan(:) , name(:) , ...
        'UniformOutput' , false )' ] ;

  % Concatenate column headers with comma delimiter
  txt.meas{ 1 } = strjoin( txt.meas{ 1 } , ',' ) ;

  % Build formatting string for each line of data
  fmt = [ '%.9f' , repmat( ',%.9f', 1, par.chans * N ) , '\n' ] ;

  % Next, format all measurements in string. One line per input voltage.
  txt.meas{ 2 } = sprintf( fmt , [ volts ; mW ] ) ;

  % Join header and data
  txt.meas = strjoin( txt.meas , '\n' ) ;

  % Format output file names
  fnam.coef = fullfile( par.tabledir , par.coefftable ) ;
  fnam.meas = fullfile( par.tabledir , par.powertable ) ;

  % Error flag
  errflg = false ;

  % Save binary copies of the data
  try
    save( fnam.coef , 'wlen' , 'name' , 'ipos' , 'chan' , 'C' , 'pp' )
    save( fnam.meas , 'wlen' , 'name' , 'ipos' , 'chan' , 'volts' , 'mW' )
  catch
    errflg = true ;
  end

  % Add .csv file name extensions
  fnam.coef = [ fnam.coef , '.csv' ] ;
  fnam.meas = [ fnam.meas , '.csv' ] ;

  % Write text copies of the data to CSV tables
  errflg = errflg || ...
    char2file( fnam.coef , txt.coef ) || char2file( fnam.meas , txt.meas );

  % There was an error while writing to file
  if  errflg

    % Instruct user
    waitfor( warndlg( [ 'Failed to save data. ' , ...
      'Save binary data to specified file.' ] ) )

    % Save data
    uisave( { 'wlen' , 'volts' , 'mW' , 'C' } , 'makelasertable.mat' )

    % Done
    error( 'Failed to save data.' )

  end % write to file


  %%% Plot results %%%

  % Evaluation points, in volts
  x = par.range( 1 ) : diff( par.range ) / 1e3 : par.range( 2 ) ;

  % Allocate vector of figures
  fig = gobjects( 1 , N ) ;

  % Lasers
  for  i = 1 : N

    % New figure
    fig( i ) = figure( 'Visible' , 'off' ) ;

    % Show empirical measurements
    scatter( volts , mW( i , : ) ) ;  hold on

    % Show best fitting transfer function
    plot( x , transfer( C( i , : ) , x ) , 'LineWidth' , 2 )

    % Formatting
    ax = gca ;
    set( ax , 'LineWidth' , 1 , 'TickDir' , 'out' , 'FontSize' , 12 )
    ax.Children( 1 ).Color = ax.ColorOrder( 3 , : ) ;
    axis square , grid on

    % Labels
    xlabel( 'Input Volts' )
    ylabel( 'Emission power (mW)' )
    title( sprintf( 'Laser%d\\_%dnm' , ipos( i ) , wlen( i ) ) )
    legend( { 'Data' , 'Model' } , 'FontSize' , 12 , ...
      'Location' , 'northwest' )

  end % lasers

  % Show results
  set( fig , 'Visible' , 'on' )

  
end % makelasertable


% Write given string to given file as ASCII. Returns 0 on success. Non-zero
% on failure.
function  err = char2file( fnam , txt )

  % Expect disaster
  err = true ;

  % Open file with write permissions
  [ fid , msg ] = fopen( fnam , 'w' , 'n' , 'US-ASCII' ) ;

  % Failed to open file
  if  fid == -1
    warning( 'Failed to open %s with error: %s' , fnam , msg )
    return
  end

  % Write string to file
  N = fprintf( fid , '%s' , txt ) ;

  % Failed to write entire string
  if  N < numel( txt )
    warning( 'Wrote %d of %d characters to file %s.' , ...
      N , numel( txt ) , fnam )
    return
  end

  % Close the file
  if  fclose( fid ) == -1
    warning( 'Failed to close file %s.' , fnam )
    return
  end

  % No disaster
  err = false ;
  
end % char2file

