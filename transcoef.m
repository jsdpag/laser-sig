
function  C = transcoef( V , mW )
% 
% C = transcoef( V , mW )
% 
% A convenience function that finds the best-fitting set of coefficients
% for the laser transfer function transfer( ) using least-squares,
% non-linear regression.
% 
% Written by Jackson Smith - November 2022 - Fries Lab (ESI Frankfurt)
% 
  
  % Input checking
  narginchk ( 2 , 2 )
  nargoutchk( 0 , 1 )
  
  % Valid numeric arrays
  validnumber(  V ,  'V' )
  validnumber( mW , 'mW' )

  % Cast to double if necessary
  if  ~ isa(  V , 'double' ) ,  V = double(  V ) ; end
  if  ~ isa( mW , 'double' ) , mW = double( mW ) ; end

  % Make sure that number of elements are equal
  if  numel( V ) ~= numel( mW )
    error( 'Input args require same number of elements.' )
  end

  % Make both into column vectors, if necessary
  if  ~ iscolumn(  V ) ,  V =  V( : ) ; end
  if  ~ iscolumn( mW ) , mW = mW( : ) ; end

  % Find minimum input value and corresponding linear index
  [ vmin , imin ] = min( V ) ;

  % Default starting coefficients + lower and upper bounds
  C0 = [ mW( imin ) , 1 , 0.25 , 1 , 1 ] ;
  LB = [          0 , 0 , 0.00 , 0 , 0 ] ;
  UB = inf( 1 , 5 ) ;

  % Non-zero starting baseline
  if  vmin == 0 , LB( 1 ) = mW( imin ) ; end

  % Disable lsqcurvefit verbosity
  opt = optimoptions( 'lsqcurvefit' , 'Display' , 'none' ) ;

  % Find best-fitting coefficients
  C = lsqcurvefit( @transfer , C0 , V , mW , LB , UB , opt ) ;

end % transcoef


% Check that input is a valid numeric array
function  validnumber( A , name )
  
  % Evaluate array for validity. This is what we want to have.
  val = isnumeric( A )  &&  isreal( A )  &&  all( isfinite( A ) )  &&  ...
    all( A >= 0 , 'all' ) ;

  % Invalid number, raise an error
  if  ~ val
    error( [ '%s must be a real-valued, finite, zero or positive ' , ...
      'numeric array' ] , name )
  end

end % validnumber

