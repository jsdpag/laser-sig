
function  Y = transfer( C , X , invflg )
% 
% mW = transfer( C ,  V )
%  V = transfer( C , mW , '-inverse' )
% 
% Predict laser output power in mW from input in V using coefficients C.
% The transfer function starts off using a power function at low values of
% V, but switches to a linear function above some transition voltage. This
% is appropriate for modelling the output of certain diode lasers e.g.
% LuxX+ from Omicron Laserage.
% 
% C = [ B , M , V0 , P , Vt ], where B is the baseline, M is the scaling
%   factor, V0 is the amount horizontal shift along the voltage axis, and P
%   is the power coefficient. Vt is the transition point at which the power
%   function switches into a linear function.
% 
% Let f(v) = B + M(v-V0)^P and f'(v) = MP(v-V0)^(P-1), if v >= V0.
% Let f(v) = B and f'(v) = 0, if v < V0.
%
% The output is computed as:
%
%   mW = f(v) if v <= Vt
%   mW = f(Vt) + f'(Vt)(V-Vt) if v > Vt
% 
% Optional third input argument may be the flag '-inverse' in which case
% the inverse function is computed such that the voltage to obtain a
% desired power output is returned.
% 
% If C or X is empty then returns empty [ ] in Y.
% 
% Written by Jackson Smith - November 2022 - Fries Lab (ESI Frankfurt)
% 
  
  % Input arg checks
   narginchk( 2 , 3 )
  nargoutchk( 0 , 1 )

  % Empty input detected, return empty and quit
  if  isempty( C )  ||  isempty( X ) , Y = [ ] ; return , end

  % Check that C and X are valid numeric arrays
  validnumber( C , 'C' )
  validnumber( X , 'X' )

  % C must contain 5 terms
  if  numel( C ) ~= 5
    error( 'Expecting 5 terms in C.' )
  end
  
  % Signal use of regular forward transfer function by default
  inv = false ;

  % Check for third input arg
  if  nargin > 2

    % Must be a classic string
    if  ~ ( ischar( invflg ) && isrow( invflg ) )
      error( '3rd input arg must be char row vector i.e. classic string' )
    end
    
    % Check value of string
    switch  invflg
      case  '-inverse' , inv = true ; % Signal inverse transfer function
      otherwise , error( 'Invalid 3rd input arg, expecting ''-inverse''' )
    end

  end % 3rd input arg
  
  % Map coefficients to meaningful names
   B = C( 1 ) ;
   M = C( 2 ) ;
  V0 = C( 3 ) ;
   P = C( 4 ) ;
  Vt = C( 5 ) ;
  
  % Find power level and slope at Vt
  y0 =  func( B , M , V0 , P , Vt ) ;
  s0 = deriv(     M , V0 , P , Vt ) ;

  % Allocate output
  Y = zeros( size( X ) ) ;

  % Identify non-linear section when using ...
  if  inv
    i = X <= y0 ; % ... inverse function.
  else
    i = X <= Vt ; % ... forward function.
  end

  % Apply ...
  if  inv
    Y( i ) = nthroot( max( 0 , X( i ) - B ) ./ M , P ) + V0 ; % inverse.
  else
    Y( i ) = func( B , M , V0 , P , X( i ) ) ; % ... forward function.
  end
  
  % Linear section
  i = ~ i ;

  % Apply ...
  if  inv
    Y( i ) = ( X( i ) - y0 ) ./ s0 + Vt ; % ... inverse linear function.
  else
    Y( i ) = y0 + s0 .* ( X( i ) - Vt ) ; % ... forward linear function.
  end
  
end % transfer


% Power function, forward
function  mW = func( B , M , V0 , P , volts )
  mW = B + M .* max( 0 , volts - V0 ) .^ P ;
end


% First derivative of power function
function  slope = deriv( M , V0 , P , volts )
  slope = M .* P .* max( 0 , volts - V0 ) .^ ( P - 1 ) ;
end


% Check that input is a valid numeric array
function  validnumber( A , name )
  
  % Evaluate array for validity. This is what we want to have.
  val = isa( A , 'double' ) && isreal( A ) && all( isfinite( A ) ) && ...
    all( A >= 0 , 'all' ) ;

  % Invalid number, raise an error
  if  ~ val
    error( [ '%s must be a real-valued, finite, zero or positive ' , ...
      'double array' ] , name )
  end

end % validnumber

