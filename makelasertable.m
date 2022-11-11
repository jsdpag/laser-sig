
function  makelasertable( varargin )
% 
% makelasertable wlen0 [wlen1] [wlen2] ...
% 
% Helper function that partially automates the process of measuring and
% estimating the transfer function for a set of lasers. 

% then writing a CSV
% table called 'lasers.csv' that 
% 
  
  
  %%% Parameters %%%
  
  % Parameter file name and directory
  parnam = 'makelasertable.csv' ;
  pardir = fileparts( which( 'makelasertable' ) ) ;
  
  % Read in parameter file as char row vector
  par = fileread( fullfile( pardir , parnam ) ) ;

  % Separate by newline and comma delimiter characters
  par = strsplit( par , { '\n' , ',' } ) ;

  % Reconfigure into 2 x num-pars cell array of classic strings
  par = reshape( par , 2 , [ ] ) ;

  % Convert into struct, fields name parameters and contain their values
  par = struct( par{ : } ) ;

  % List of constant name/value input args for LaserInputOutputMeasure
  CARGIN = { 'host' , par.host , 'lasertester' , par.lasertester , ...
    'input' , str2double( par.input ) , 'measurement' , par.measurement } ;

  % Method specific constant input args
  switch  par.measurement

    % Semi-automated measurement using ThorLabs PM100D. Get duration of
    % timer.
    case  'pm100d' , CARGIN = [ CARGIN , ...
                    { 'pm100d_timer' , str2double( par.pm100d_timer ) } ] ;

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
  
  % Allocate vector of laser wavelengths to measure
  wlen = zeros( N , 1 ) ;

  % Input args
  for  i = 1 : N

    % Check if arg is char row vector
    if  ~( ischar( varargin{ i } ) && isrow( varargin{ i } ) )
      error( 'Input arg %d is not classic string (char row vector)' , i )
    end

    % Convert to double floating point
    wlen( i ) = str2double( varargin{ i } ) ;

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


  %%% Measure transfer functions %%%

  % Allocate cell array, one cell per wavelength
  in2out = cell( N , 1 ) ;

  % Lasers
  for  i = 1 : N

    % Gather together variable name/value args for LaserInputOutputMeasure

    % Method specific args
    switch  par.measurement

      % Semi-automated measurement using ThorLabs PM100D.
      case  'pm100d'

        % Determine wavelength coefficient field name. Then parse value.
        fnam = sprintf( 'pm100d_coef_%dnm' , wlen( i ) ) ;
        vargin = { 'pm100d_coefficient' , str2double( par.( fnam ) ) } ;

    end % method specific args

    % Prompt user to set the measurement device for this laser's wavelength
    waitfor( warndlg( [ ...
      'Please prepare to measure %dnm laser power output.' , newline , ...
        'Click OK when done.' ] ) )

    % Measure this laser's transfer function
    in2out{ i } = LaserInputOutputMeasure( CARGIN{ : } , vargin{ : } ) ;

  end % lasers


  %%% Find best-fitting transfer function coefficients %%%

  % Get one copy of tested input voltages
  volts = in2out{ 1 }.input_V ;

  % Check that the same voltages were tested across lasers
  if  ~ all( cellfun( @( c ) isequal( volts , c.input_V ) , in2out ) )
    error( 'Voltage input mismatch across measured lasers.' )
  end

  % Concatenate measured output power. Columns in register with voltages.
  % Row index in register with wlen and argument input order.
  mW = [ in2out{ : } ] ;
  mW = cat( 1 , mW.output_mW ) ;

  % Allocate coefficients for each laser. Rows index lasers. Cols ind coef.
  C = zeros( N , 4 ) ;

  % Best-fitting coefficients for each laser
  for  i = 1 : N , C( i , : ) = transcoef( volts , mW( i , : ) ) ; end


  %%% Write output tables %%%

  % Allocate cell array for coefficients table, one row per laser and one
  % more for the header
  txt.coef = cell( 1 , N + 1 ) ;

  % Define header
  txt.coef{ 1 } = 'index,nm,B,M,P,v0' ;

  % Lasers
  for  i = 1 : N
    txt.coef{ i + 1 } = sprintf( '%d,%d,%.9f,%.9f,%.9f,%.9f' , ...
      i - 1 , wlen( i ) , C( i , : ) ) ;
  end

  % Concatenate into string with newlines
  txt.coef = strjoin( txt.coef , '\n' ) ;

  % Now allocate for the measured transfer functions
  txt.meas = cell( 1 , 2 ) ;

  % Column headers, identifying each laser for each power column
  txt.meas{ 1 } = [ { 'Volts' } , ...
    arrayfun( @( i , nm ) sprintf( 'Laser%d_%dnm' , i , nm ) , ...
      0 : N - 1 , wlen , 'UniformOutput' , false ) ] ;

  % Concatenate column headers with comma delimiter
  txt.meas{ 1 } = strjoin( txt.meas{ 1 } , ',' ) ;

  % Next, format all measurements in string. One line per input voltage.
  txt.meas{ 2 } = sprintf( [ '%.9f' , repmat( ',%.9f', 1, N ) , '\n' ] ,...
    [ volts ; mW ] ) ;

  % Join header and data
  txt.meas = strjoin( txt.meas , '\n' ) ;

  % Format output file names
  fnam.coef = fullfile( par.tabledir , par.coefftable ) ;
  fnam.meas = fullfile( par.tabledir , par.powertable ) ;

  % Write to file
  if  char2file( fnam.coef , txt.coef ) || char2file( fnam.meas , txt.meas )

    % Instruct user
    waitfor( warndlg( [ 'Failed to write table. ' , ...
      'Save binary data to specified file.' ] ) )

    % Save data
    uisave( { 'wlen' , 'volts' , 'mW' , 'C' } , 'makelasertable.mat' )

    % Done
    error( 'Failed to write tables.' )

  end % write to file


  %%% Plot results %%%

  % Evaluation points, in volts
  x = 0 : 0.001 : 5 ;

  % Allocate vector of figures
  fig = gobjects( 1 , N ) ;

  % Lasers
  for  i = 1 : N

    % New figure
    fig( i ) = figure( 'Visible' , 'off' ) ;

    % Show empirical measurements
    scatter( volts , mW( i , : ) ) ;  hold on

    % Show best fitting transfer function
    plot( x , transfer( C( i , : ) , x ) , 'LineWidth' , 1 )

    % Formatting
    set( gca , 'LineWidth' , 1 , 'TickDir' , 'out' , 'FontSize' , 12 )

    % Labels
    xlabel( 'Input Volts' )
    ylabel( 'Emission power (mW)' )
    title( sprintf( 'Laser%d_%dnm' , i - 1 , wlen( i ) ) )

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

