
function  Y = transfer( C , X , invflg )
% 
% mW = transfer( C ,  V )
%  V = transfer( C , mW , '-inverse' )
% 
% Predict laser output power in mW from input in V using coefficients C.
% The transfer function starts off using a power function at low values of
% V, but switches to a linear function above some threshold voltage. This
% is appropriate for modelling the output of certain diode lasers e.g.
% LuxX+ from Omicron Laserage.
% 
% C = [ B , M , P , v0 ], where B is the baseline, M is the scaling factor,
%   and P is the power coefficient. v0 is the point at which the power
%   function switches into a linear function.
% 
% mW = B + MV^P if V <= v0
% mW = B + Mv0^P + (V-v0)MPv0^(P-1) if V > v0
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

  % No third input arg
  else

    % Signal use of regular forward transfer function
    inv = false ;

  end % 3rd input arg
  
  % Map coefficients to meaningful names
   B = C( 1 ) ;
   M = C( 2 ) ;
   P = C( 3 ) ;
  v0 = C( 4 ) ;
  
  % Find power level and slope at v0
  y0 =  func( B , M , P , v0 ) ;
  s0 = deriv(     M , P , v0 ) ;

  % Allocate output
  Y = zeros( size( X ) ) ;

  % Identify non-linear section when using ...
  if  inv
    i = X <= y0 ; % ... inverse function.
  else
    i = X <= v0 ; % ... forward function.
  end

  % Apply ...
  if  inv
    Y( i ) = nthroot( ( X( i ) - B ) ./ M , P ) ; % inverse.
  else
    Y( i ) = func( B , M , P , X( i ) ) ; % ... forward function.
  end
  
  % Linear section
  i = ~ i ;

  % Apply ...
  if  inv
    Y( i ) = ( X( i ) - y0 ) ./ s0 + v0 ; % ... inverse linear function.
  else
    Y( i ) = y0 + s0 .* ( X( i ) - v0 ) ; % ... forward linear function.
  end
  
end % transfer


% Power function, forward
function  mW = func( B , M , P , volts )
  mW = B + M .* volts .^ P ;
end


% First derivative of power function
function  slope = deriv( M , P  , volts )
  slope = M .* P .* volts .^ ( P - 1 ) ;
end


% Check that input is a valid numeric array
function  validnumber( A , name )
  
  % Evaluate array for validity. This is what we want to have.
  val = isa( A , 'double' )  &&  isreal( A )  &&  all( isfinite( A ) ) ;

  % Invalid number, raise an error
  if  ~ val
    error( '%s must be a real-valued, finite, double array' , name )
  end

end % validnumber

