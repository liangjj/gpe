!Copyright 2011 Anthony Youd/Newcastle University
!
!   Licensed under the Apache License, Version 2.0 (the "License");
!   you may not use this file except in compliance with the License.
!   You may obtain a copy of the License at
!
!       http://www.apache.org/licenses/LICENSE-2.0
!
!   Unless required by applicable law or agreed to in writing, software
!   distributed under the License is distributed on an "AS IS" BASIS,
!   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
!   See the License for the specific language governing permissions and
!   limitations under the License.

module derivs
  ! Routines to calculate finite-difference derivatives
  use parameters
  implicit none

  private
  public :: deriv_x, deriv_y, deriv_z, deriv_xx, deriv_yy, deriv_zz

  contains

  subroutine deriv_x(f,fx)
    ! First x-derivative
    use parameters
    implicit none

    complex (pr), dimension(0:nx1,js-2:je+2,ks-2:ke+2), intent(in)  :: f
    complex (pr), dimension(0:nx1,js:je,ks:ke), intent(out) :: fx
    integer, dimension(2) :: minus=0, plus=0
    integer :: i, j, k

    select case (order)
      case (2)
        ! Second order centred difference
        do k=ks,ke
          do j=js,je
            do i=0,nx1
              call second_index(i, nx1, minus, plus, .true.)

              fx(i,j,k) = ( f(plus(1),j,k) - f(minus(1),j,k) ) / (2.0_pr*dx)
            end do
          end do
        end do
      case (4)
        ! Fourth order centred difference
        do k=ks,ke
          do j=js,je
            do i=0,nx1
              call fourth_index(i, nx1, minus, plus, .true.)

              fx(i,j,k) = ( -f(plus(2),j,k) + &
                      8.0_pr*f(plus(1),j,k) - &
                      8.0_pr*f(minus(1),j,k) + &
                             f(minus(2),j,k) ) / (12.0_pr*dx)
            end do
          end do
        end do
    end select

    return
  end subroutine deriv_x
  
! ***************************************************************************  
  
  subroutine deriv_y(f,fy)
    ! First y-derivative
    use parameters
    implicit none

    complex (pr), dimension(0:nx1,js-2:je+2,ks-2:ke+2), intent(in)  :: f
    complex (pr), dimension(0:nx1,js:je,ks:ke), intent(out) :: fy
    integer, dimension(2) :: minus=0, plus=0
    integer :: j, k

    select case (order)
      case (2)
        ! Second order centred difference
        do k=ks,ke
          do j=js,je
            call second_index(j, ny1, minus, plus, .false.)

            fy(:,j,k) = ( f(:,plus(1),k) - f(:,minus(1),k) ) / (2.0_pr*dy)
          end do
        end do
      case (4)
        ! Fourth order centred difference
        do k=ks,ke
          do j=js,je
            call fourth_index(j, ny1, minus, plus, .false.)

            fy(:,j,k) = ( -f(:,plus(2),k) + &
                    8.0_pr*f(:,plus(1),k) - &
                    8.0_pr*f(:,minus(1),k) + &
                           f(:,minus(2),k) ) / (12.0_pr*dy)
          end do
        end do
    end select

    return
  end subroutine deriv_y
  
! ***************************************************************************  

  subroutine deriv_z(f,fz)
    ! First z-derivative
    use parameters
    implicit none

    complex (pr), dimension(0:nx1,js-2:je+2,ks-2:ke+2), intent(in)  :: f
    complex (pr), dimension(0:nx1,js:je,ks:ke), intent(out) :: fz
    integer, dimension(2) :: minus=0, plus=0
    integer :: j, k

    select case (order)
      case (2)
        ! Second order centred difference
        do k=ks,ke
          do j=js,je
            call second_index(k, nz1, minus, plus, .false.)

            fz(:,j,k) = ( f(:,j,plus(1)) - f(:,j,minus(1)) ) / (2.0_pr*dz)
          end do
        end do
      case (4)
        ! Fourth order centred difference
        do k=ks,ke
          do j=js,je
            call fourth_index(k, nz1, minus, plus, .false.)

            fz(:,j,k) = ( -f(:,j,plus(2)) + &
                    8.0_pr*f(:,j,plus(1)) - &
                    8.0_pr*f(:,j,minus(1)) + &
                           f(:,j,minus(2)) ) / (12.0_pr*dz)
          end do
        end do
    end select

    return
  end subroutine deriv_z

! ***************************************************************************  

  subroutine deriv_xx(f,fxx)
    ! Second x-derivative
    use parameters
    implicit none

    complex (pr), dimension(0:nx1,js-2:je+2,ks-2:ke+2), intent(in)  :: f
    complex (pr), dimension(0:nx1,js:je,ks:ke), intent(out) :: fxx
    integer, dimension(2) :: minus=0, plus=0
    integer :: i, j, k

    select case (order)
      case (2)
        ! Second order centred difference
        do k=ks,ke
          do j=js,je
            do i=0,nx1
              call second_index(i, nx1, minus, plus, .true.)

              fxx(i,j,k) = ( f(plus(1),j,k) - &
                      2.0_pr*f(i,j,k) + &
                             f(minus(1),j,k) ) / dx2
            end do
          end do
        end do
      case (4)
        ! Fourth order centred difference
        do k=ks,ke
          do j=js,je
            do i=0,nx1
              call fourth_index(i, nx1, minus, plus, .true.)

              fxx(i,j,k) = ( -f(plus(2),j,k) + &
                      16.0_pr*f(plus(1),j,k) - &
                      30.0_pr*f(i,j,k) + &
                      16.0_pr*f(minus(1),j,k) - &
                              f(minus(2),j,k) ) / (12.0_pr*dx2)
            end do
          end do
        end do
    end select

    return
  end subroutine deriv_xx

! ***************************************************************************  

  subroutine deriv_yy(f,fyy)
    ! Second y-derivative
    use parameters
    implicit none

    complex (pr), dimension(0:nx1,js-2:je+2,ks-2:ke+2), intent(in)  :: f
    complex (pr), dimension(0:nx1,js:je,ks:ke), intent(out) :: fyy
    integer, dimension(2) :: minus=0, plus=0
    integer :: j, k

    select case (order)
      case (2)
        ! Second order centred difference
        do k=ks,ke
          do j=js,je
            call second_index(j, ny1, minus, plus, .false.)

            fyy(:,j,k) = ( f(:,plus(1),k) - &
                    2.0_pr*f(:,j,k) + &
                           f(:,minus(1),k) ) / dy2
          end do
        end do
      case (4)
        ! Fourth order centred difference
        do k=ks,ke
          do j=js,je
            call fourth_index(j, ny1, minus, plus, .false.)
          
            fyy(:,j,k) = ( -f(:,plus(2),k) + &
                    16.0_pr*f(:,plus(1),k) - &
                    30.0_pr*f(:,j,k) + &
                    16.0_pr*f(:,minus(1),k) - &
                            f(:,minus(2),k) ) / (12.0_pr*dy2)
          end do
        end do
    end select

    return
  end subroutine deriv_yy
  
! ***************************************************************************  

  subroutine deriv_zz(f,fzz)
    ! Second z-derivative
    use parameters
    implicit none

    complex (pr), dimension(0:nx1,js-2:je+2,ks-2:ke+2), intent(in)  :: f
    complex (pr), dimension(0:nx1,js:je,ks:ke), intent(out) :: fzz
    integer, dimension(2) :: minus=0, plus=0
    integer :: j, k

    select case (order)
      case (2)
        ! Second order centred difference
        do k=ks,ke
          do j=js,je
            call second_index(k, nz1, minus, plus, .false.)

            fzz(:,j,k) = ( f(:,j,plus(1)) - &
                    2.0_pr*f(:,j,k) + &
                           f(:,j,minus(1)) ) / dz2
          end do
        end do
      case (4)
        ! Fourth order centred difference
        do k=ks,ke
          do j=js,je
            call fourth_index(k, nz1, minus, plus, .false.)
          
            fzz(:,j,k) = ( -f(:,j,plus(2)) + &
                    16.0_pr*f(:,j,plus(1)) - &
                    30.0_pr*f(:,j,k) + &
                    16.0_pr*f(:,j,minus(1)) - &
                            f(:,j,minus(2)) ) / (12.0_pr*dz2)
          end do
        end do
    end select

    return
  end subroutine deriv_zz

! ***************************************************************************  

  subroutine second_index(indx, n, minus, plus, x_deriv)
    ! Determine the indices at the boundaries depending on whether periodic or
    ! reflective boundaries are chosen in the case of second order differences
    implicit none

    integer, intent(in) :: indx, n
    logical, intent(in) :: x_deriv
    integer, dimension(2), intent(out) :: minus, plus
    
    select case (bcs)
      case (1)
        ! periodic BCs
        minus(1) = indx-1
        plus(1) = indx+1
        if (x_deriv) then
          ! Only need to define BCs for the x-direction which is not
          ! calculated in parallel
          if (indx == 0) then
            minus(1) = n
            plus(1) = 1
          end if
          if (indx == n) then
            minus(1) = n-1
            plus(1) = 0
          end if
        end if
      case (2)
        ! reflective BCs
        minus(1) = indx-1
        plus(1) = indx+1
        if (indx == 0) then
          minus(1) = 1
          plus(1) = 1
        end if
        if (indx == n) then
          minus(1) = n-1
          plus(1) = n-1
        end if
    end select

    return
  end subroutine second_index
  
! ***************************************************************************  

  subroutine fourth_index(indx, n, minus, plus, x_deriv)
    ! Determine the indices at the boundaries depending on whether periodic or
    ! reflective boundaries are chosen in the case of fourth order differences
    implicit none

    integer, intent(in) :: indx, n
    logical, intent(in) :: x_deriv
    integer, dimension(2), intent(out) :: minus, plus
    
    select case (bcs)
      case (1)
        ! periodic BCs
        minus(1) = indx-1
        minus(2) = indx-2
        plus(1) = indx+1
        plus(2) = indx+2
        if (x_deriv) then
          ! Only need to define BCs for the x-direction which is not
          ! calculated in parallel
          if (indx == 0) then
            minus(1) = n
            minus(2) = n-1
            plus(1) = 1
            plus(2) = 2
          end if
          if (indx == 1) then
            minus(1) = 0
            minus(2) = n
            plus(1) = 2
            plus(2) = 3
          end if
          if (indx == n-1) then
            minus(1) = n-2
            minus(2) = n-3
            plus(1) = n
            plus(2) = 0
          end if
          if (indx == n) then
            minus(1) = n-1
            minus(2) = n-2
            plus(1) = 0
            plus(2) = 1
          end if
        end if
      case (2)
        ! reflective BCs
        minus(1) = indx-1
        minus(2) = indx-2
        plus(1) = indx+1
        plus(2) = indx+2
        if (indx == 0) then
          minus(1) = 1
          minus(2) = 2
          plus(1) = 1
          plus(2) = 2
        end if
        if (indx == 1) then
          minus(1) = 0
          minus(2) = 1
          plus(1) = 2
          plus(2) = 3
        end if
        if (indx == n-1) then
          minus(1) = n-2
          minus(2) = n-3
          plus(1) = n
          plus(2) = n-1
        end if
        if (indx == n) then
          minus(1) = n-1
          minus(2) = n-2
          plus(1) = n-1
          plus(2) = n-2
        end if
    end select

    return
  end subroutine fourth_index

! ***************************************************************************  

end module derivs
