!   This file is part of EmDee.
!
!    EmDee is free software: you can redistribute it and/or modify
!    it under the terms of the GNU General Public License as published by
!    the Free Software Foundation, either version 3 of the License, or
!    (at your option) any later version.
!
!    EmDee is distributed in the hope that it will be useful,
!    but WITHOUT ANY WARRANTY; without even the implied warranty of
!    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!    GNU General Public License for more details.
!
!    You should have received a copy of the GNU General Public License
!    along with EmDee. If not, see <http://www.gnu.org/licenses/>.
!
!    Author: Charlles R. A. Abreu (abreu@eq.ufrj.br)
!            Applied Thermodynamics and Molecular Simulation
!            Federal University of Rio de Janeiro, Brazil

module models

use global

implicit none

integer(ib), parameter :: mCOULOMB = 10000

integer(ib), parameter :: mNONE     = 0, &  ! No model
                          mLJ       = 1, &  ! Lennard-Jones
                          mLJSF     = 2, &  ! Lennard-Jones, Shifted-Force
                          mHARMOMIC = 3, &  ! Harmonic
                          mMORSE    = 4     ! Morse

real(rb), parameter, private :: Deg2Rad = 3.14159265358979324_rb/180_rb

type tModel
  integer(ib) :: id = mNONE
  real(rb), pointer :: data(:)
  real(rb) :: p1 = zero
  real(rb) :: p2 = zero
  real(rb) :: p3 = zero
  real(rb) :: p4 = zero
  logical :: external = .true.
  type(tModel), pointer :: next => null()
end type tModel

type modelPtr
  type(tModel), pointer :: model => null()
end type modelPtr

private :: set_data

contains

!===================================================================================================
!                                      P A I R     M O D E L S
!===================================================================================================

  type(c_ptr) function EmDee_pair_none() bind(C,name="EmDee_pair_none")
    type(tModel), pointer :: model
    allocate( model )
    model%id = mNONE
    EmDee_pair_none = c_loc(model)
  end function EmDee_pair_none

!---------------------------------------------------------------------------------------------------

  type(c_ptr) function EmDee_pair_lj( epsilon, sigma ) bind(C,name="EmDee_pair_lj")
    real(rb), value   :: epsilon, sigma
    type(tModel), pointer :: model
    allocate( model )
    model = tModel( mLJ, set_data( [epsilon, sigma] ), sigma*sigma, 4.0_rb*epsilon )
    EmDee_pair_lj = c_loc(model)
  end function EmDee_pair_lj

!---------------------------------------------------------------------------------------------------

  type(c_ptr) function EmDee_pair_lj_sf( epsilon, sigma, cutoff ) bind(C,name="EmDee_pair_lj_sf")
    real(rb), value   :: epsilon, sigma, cutoff
    type(tModel), pointer :: model
    real(rb) :: sr6, sr12, eps4, Ec, Fc
    sr6 = (sigma/cutoff)**6
    sr12 = sr6*sr6
    eps4 = 4.0_rb*epsilon
    Ec = eps4*(sr12 - sr6)
    Fc = 6.0_rb*(eps4*sr12 + Ec)/cutoff
    Ec = -(Ec + Fc*cutoff)
    allocate( model )
    model = tModel( mLJSF, set_data( [epsilon, sigma, cutoff] ), sigma**2, eps4, Fc, Ec )
    EmDee_pair_lj_sf = c_loc(model)
  end function EmDee_pair_lj_sf

!===================================================================================================
!                                     M I X I N G     R U L E S
!===================================================================================================

  function cross_pair( imodel, jmodel ) result( ijmodel )
    type(c_ptr),  intent(in) :: imodel, jmodel
    type(c_ptr)              :: ijmodel

    type(tModel), pointer :: i, j, ij

    if (c_associated(imodel).and.c_associated(jmodel)) then
      call c_f_pointer( imodel, i )
      call c_f_pointer( jmodel, j )
      if (match(mLJ,mLJ)) then
        ijmodel = EmDee_pair_lj( geometric(1), arithmetic(2) )
      else if (match(mLJSF,mLJSF)) then
        ijmodel = EmDee_pair_lj_sf( geometric(1), arithmetic(2), arithmetic(3) )
      else if (match(mLJ,mNONE).or.match(mLJSF,mNONE)) then
        ijmodel = EmDee_pair_none()
      else
        ijmodel = c_null_ptr
      end if
    else
      ijmodel = c_null_ptr
    end if

    if (c_associated(ijmodel)) then
      call c_f_pointer( ijmodel, ij )
      ij%external = .false.
    end if

    contains
      !- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      logical function match( a, b )
        integer(ib), intent(in) :: a, b
        match = ((i%id == a).and.(j%id == b)).or.((i%id == b).and.(j%id == a))
      end function match
      !- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      real(rb) function arithmetic( k )
        integer(ib), intent(in) :: k
        arithmetic = 0.5_rb*(i%data(k) + j%data(k))
      end function arithmetic
      !- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      real(rb) function geometric( k )
        integer(ib), intent(in) :: k
        geometric = sqrt(i%data(k)*j%data(k))
      end function geometric
      !- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  end function cross_pair

!===================================================================================================
!                                      B O N D     M O D E L S
!===================================================================================================

  type(c_ptr) function EmDee_bond_harmonic( k, r0 ) bind(C,name="EmDee_bond_harmonic")
    real(rb), value :: k, r0
    type(tModel), pointer :: model
    allocate( model )
    model = tModel( mHARMOMIC, set_data( [k, r0] ), r0, -k, 0.5_rb*k )
    EmDee_bond_harmonic = c_loc(model)
  end function EmDee_bond_harmonic

!---------------------------------------------------------------------------------------------------

  type(c_ptr) function EmDee_bond_morse( D, alpha, r0 ) bind(C,name="EmDee_bond_morse")
    real(rb), value :: D, alpha, r0
    type(tModel), pointer :: model
    allocate( model )
    model = tModel( mMORSE, set_data( [D, alpha, r0] ), r0, -alpha, D, -2.0_rb*D*alpha )
    EmDee_bond_morse = c_loc(model)
  end function EmDee_bond_morse

!===================================================================================================
!                                    A N G L E     M O D E L S
!===================================================================================================

  type(c_ptr) function EmDee_angle_harmonic( k, theta0 ) bind(C,name="EmDee_angle_harmonic")
    real(rb), value :: k, theta0
    type(tModel), pointer :: model
    allocate( model )
    model = tModel( mHARMOMIC, set_data( [k, theta0] ), Deg2Rad*theta0, -k, 0.5_rb*k )
    EmDee_angle_harmonic = c_loc(model)
  end function EmDee_angle_harmonic

!===================================================================================================
!                                 D I H E D R A L     M O D E L S
!===================================================================================================

  type(c_ptr) function EmDee_dihedral_harmonic( k, phi0 ) bind(C,name="EmDee_dihedral_harmonic")
    real(rb), value :: k, phi0
    type(tModel), pointer :: model
    allocate( model )
    model = tModel( mHARMOMIC, set_data( [k, phi0] ), 0.0_rb, Deg2Rad*phi0, -k, 0.5_rb*k )
    EmDee_dihedral_harmonic = c_loc(model)
  end function EmDee_dihedral_harmonic

!===================================================================================================
!                             A U X I L I A R Y     P R O C E D U R E
!===================================================================================================

  function set_data( values ) result( data )
    real(rb), intent(in) :: values(:)
    real(rb), pointer    :: data(:)
    allocate( data(size(values)) )
    data = values
  end function set_data

!===================================================================================================

end module models
