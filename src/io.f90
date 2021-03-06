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

module io
  ! Routines for input/output
  use parameters
  implicit none

  private
  public :: open_files, close_files, save_time, save_energy, &
    save_velocity_pdf, save_vel_corr, save_surface, idl_surface, end_state, &
    get_zeros, get_re_im_zeros, get_extra_zeros, save_linelength, &
    save_momentum, save_norm, get_dirs, diag, condensed_particles, &
    average, pp_save_filter, save_run, read_run_params, print_runtime_info
  
  contains

  function itos(n)
    ! Convert an integer into a string of length 7
    implicit none

    integer, intent(in) :: n 
    integer :: i, n_, d(7)
    character(7) :: itos
    character :: c(0:9) = (/'0','1','2','3','4','5','6','7','8','9'/)

    n_ = n
    do i = 7, 1, -1
      d(i) = mod(n_,10)
      n_ = n_ / 10
    end do

    itos = c(d(1))//c(d(2))//c(d(3))//c(d(4))//c(d(5))//c(d(6))//c(d(7))

    return
  end function itos

! ***************************************************************************  

  subroutine open_files()
    ! Open runtime files
    implicit none

    if (myrank == 0) then
      open (99, file='RUNNING')
      close (99)
    end if

    return
  end subroutine open_files

! ***************************************************************************  

  subroutine close_files()
    ! Close runtime files
    implicit none

    if (myrank == 0) then
      close (97)
    end if

    return
  end subroutine close_files

! ***************************************************************************  

  subroutine read_run_params()
    ! Read run-time parameters from run.in.
    use error, only : emergency_stop
    use ic, only : unit_no
    use parameters
    implicit none
  
    integer :: ioerr
    character(5) :: cioerr = '*****'

    open (unit_no, file='run.in')
    read (unit_no, nml=run_params, iostat=ioerr)
    if (ioerr /= 0) call nml_error('run_params', ioerr)
    read (unit_no, nml=eqn_params, iostat=ioerr)
    if (ioerr /= 0) call nml_error('eqn_params', ioerr)
    read (unit_no, nml=io_params, iostat=ioerr)
    if (ioerr /= 0) call nml_error('io_params', ioerr)
    read (unit_no, nml=misc_params, iostat=ioerr)
    if (ioerr /= 0) call nml_error('misc_params', ioerr)
    close (unit_no)

    contains

    subroutine nml_error(nl, ioerr)
      implicit none

      character(*), intent(in) :: nl
      integer, intent(in) :: ioerr

      close (unit_no)
      write (cioerr, '(i5.4)') ioerr
      call emergency_stop('ERROR: There was an error reading namelist '//nl// &
        ' in run.in: iostat='//cioerr//'.')

      return
    end subroutine nml_error
  end subroutine read_run_params

! ***************************************************************************  

  subroutine get_dirs()
    ! Get named directories where each process can write its own data
    use parameters
    implicit none

    ! Directory names are proc** with ** replaced by the rank of each process
    if (myrank < 10) then
      write (proc_dir(6:6), '(1i1)') myrank
      write (proc_dir(5:5), '(1i1)') 0
    else
      write (proc_dir(5:6), '(1i2)') myrank
    end if

    ! Name of the end_state.dat file used to do a restart
    if (myrank < 10) then
      write (end_state_file(11:11), '(1i1)') myrank
      write (end_state_file(10:10), '(1i1)') 0
      write (filt_end_state_file(20:20), '(1i1)') myrank
      write (filt_end_state_file(19:19), '(1i1)') 0
    else
      write (end_state_file(10:11), '(1i2)') myrank
      write (filt_end_state_file(19:20), '(1i2)') myrank
    end if

    return
  end subroutine get_dirs

! ***************************************************************************  

  subroutine save_time(time, in_var)
    ! Save time-series data
    use parameters
    use variables, only : get_phase, get_density
    implicit none

    real (pr), intent(in) :: time
    complex (pr), dimension(0:nx1,js:je,ks:ke), intent(in) :: in_var
    real (pr), dimension(0:nx1,js:je,ks:ke) :: phase, density
    complex (pr), dimension(3) :: tmp, var
    integer :: xpos, ypos, zpos
    integer :: i, j, k

    call get_phase(in_var, phase)
    call get_density(in_var, density)

    xpos = nx/2
    ypos = ny/2
    zpos = nz/2

    tmp = 0.0_pr
    ! Find out on which process the data occurs and copy it into a temporary
    ! array
    do k=ks,ke
      do j=js,je
        do i=0,nx1
          if ((i==xpos) .and. (j==ypos) .and. (k==zpos)) then
            tmp(1) = in_var(xpos,ypos,zpos)
            tmp(2) = density(xpos,ypos,zpos)
            tmp(3) = phase(xpos,ypos,zpos)
          end if
        end do
      end do
    end do

    ! Make sure process 0 has the correct data to write
    call MPI_REDUCE(tmp, var, 3, gpe_mpi_complex, MPI_SUM, 0, &
      MPI_COMM_WORLD, ierr)

    ! Write the data to file
    if (myrank == 0) then
      open (10, status='unknown', position='append', file='psi_time.dat')
      write (10, '(6e17.9)') time, im_t, real(var(1), pr), &
        aimag(var(1)), real(var(2), pr), real(var(3), pr)
      close (10)
    end if

    return
  end subroutine save_time

! ***************************************************************************  

  subroutine save_energy(time, in_var)
    ! Save the energy
    use parameters
    use variables, only : energy
    implicit none

    real (pr), intent(in) :: time
    complex (pr), dimension(0:nx1,js-2:je+2,ks-2:ke+2), intent(in) :: in_var
    real (pr) :: E

    call energy(in_var, E)
    
    if (myrank == 0) then
      open (12, status='unknown', position='append', file='energy.dat')
      write (12, '(3e17.9)') time, im_t, E/real(nx*ny*nz, pr)
      close (12)
    end if

    return
  end subroutine save_energy
  
! ***************************************************************************  

  subroutine save_velocity_pdf(in_var)
    ! Save the velocity PDF
    use parameters
    use ic, only : x, y, z
    use variables, only : get_pdf_velocity, get_pdf
    implicit none

    complex (pr), dimension(0:nx1,js-2:je+2,ks-2:ke+2), intent(in) :: in_var
    real (pr), allocatable, dimension(:) :: vx, vy, vz
    real (pr), dimension(-nbins/2+1:nbins/2) :: pdf_vx, pdf_vy, pdf_vz, &
      gpdf_vx, gpdf_vy, gpdf_vz, vx_bins, vy_bins, vz_bins
    real (pr), dimension(3) :: vel_bins, vmax, vmean, vstdev
    integer :: i

    call get_pdf_velocity(in_var, vx, vy, vz, vmean, vstdev)
    call get_pdf(vx, pdf_vx, vmax(1))
    call get_pdf(vy, pdf_vy, vmax(2))
    call get_pdf(vz, pdf_vz, vmax(3))

    deallocate(vx)
    deallocate(vy)
    deallocate(vz)

    do i=-nbins/2+1,nbins/2
      vx_bins(i) = 2.0_pr*real(i, pr)*vmax(1)/real(nbins, pr)
      vy_bins(i) = 2.0_pr*real(i, pr)*vmax(2)/real(nbins, pr)
      vz_bins(i) = 2.0_pr*real(i, pr)*vmax(3)/real(nbins, pr)
    end do

    gpdf_vx = gaussian_pdf(vx_bins, vmean(1), vstdev(1))
    gpdf_vy = gaussian_pdf(vy_bins, vmean(2), vstdev(2))
    gpdf_vz = gaussian_pdf(vz_bins, vmean(3), vstdev(3))

    if (myrank == 0) then
      open (21, status='unknown', file='pdf/pdf_vel'//itos(p)//'.dat')
      write (21, '(a10,e17.9)') '# t:', t
      write (21, '(a10,3e17.9)') '# Mean:', vmean(1), vmean(2), vmean(3)
      write (21, '(a10,3e17.9)') '# StDev:', vstdev(1), vstdev(2), vstdev(3)
      write (21, '(a10,3e17.9)') '# Sum:', sum(pdf_vx), sum(pdf_vy), sum(pdf_vz)
      do i=-nbins/2+1,nbins/2
        write (21, '(9e17.9)') vx_bins(i), pdf_vx(i), gpdf_vx(i), &
          vy_bins(i), pdf_vy(i), gpdf_vy(i), &
          vz_bins(i), pdf_vz(i), gpdf_vz(i)
      end do
      close (21)
    end if
    
    contains

    function gaussian_pdf(pdf, mean, stdev)
      use parameters
      implicit none

      real (pr), dimension(-nbins/2+1:nbins/2), intent(in) :: pdf
      real (pr), intent(in) :: mean, stdev
      real (pr), dimension(-nbins/2+1:nbins/2) :: gaussian_pdf

      gaussian_pdf = 1.0_pr/(stdev*sqrt(2.0_pr*pi)) * &
        exp( (-0.5_pr * (pdf-mean)**2) / stdev**2 )

      return
    end function gaussian_pdf

  end subroutine save_velocity_pdf

! ***************************************************************************  

  subroutine save_vel_corr(in_var)
    ! Save the velocity correlation function.
    use parameters
    use variables, only : get_vcf
    implicit none

    complex (pr), dimension(0:nx1,js-2:je+2,ks-2:ke+2), intent(in) :: in_var
    real (pr), dimension(0:nx1) :: f
    integer :: r

    call get_vcf(in_var, f)

    if (myrank == 0) then
      open (21, status='unknown', file='vcf/vcf'//itos(p)//'.dat')
      write (21, '(a4,e17.9)') '# t:', t
      do r=0,nx1
        write (21, '(i5,e17.9)') r, f(r)
      end do
      close (21)
    end if
    
    return
  end subroutine save_vel_corr

! ***************************************************************************  

  subroutine condensed_particles(time, in_var)
    ! Calculate the mass, calculate the total energy and temperature, save
    ! spectra and save filtered isosurface
    use parameters
    use ic, only : fft, x, y, z, unit_no
    use variables, only : mass
    implicit none

    real (pr), intent(in) :: time
    complex (pr), dimension(0:nx1,js:je,ks:ke), intent(in) :: in_var
    complex (pr), dimension(0:nx1,js:je,ks:ke) :: a, filtered
    real (pr) :: M, n0, temp, temp2, tot, tmp, rho0, E0, H, k2, k4, &
      kx, ky, kz, kc, dk
    integer :: i, j, k, ii, jj, kk, ii2, jj2, kk2, V

    kc = pi !sqrt(kc2)
    dk = 2.0_pr*kc/real(nx1, pr)
    V = nx*ny*nz

    call fft(in_var, a, 'backward', .true.)

    ! Calculate the number of condensed particles
    do k=ks,ke
      do j=js,je
        if ((j==0) .and. (k==0)) then
          n0 = abs(a(0,0,0))**2
          exit
        end if
      end do
    end do

    ! Calculate the mass
    call mass(in_var, M)
    
    call MPI_BCAST(n0, 1, gpe_mpi_real, 0, MPI_COMM_WORLD, ierr)

    tmp = 0.0_pr

    ! Density of condensed particles
    rho0 = n0/V
    
    ! Total energy <H>, and temperature T (?)
    tmp = 0.0_pr
    do k=ks,ke
      kz = -kc+real(k, pr)*dk
      do j=js,je
        ky = -kc+real(j, pr)*dk
        do i=0,nx1
          kx = -kc+real(i, pr)*dk
          k2 = -(1.0_pr/12.0_pr) * &  ! minus sign by comparison with spectral
            ( ((-2.0_pr*cos(2.0_pr*kx*dx) + &
                32.0_pr*cos(kx*dx) - 30.0_pr) / dx2) + &
              ((-2.0_pr*cos(2.0_pr*ky*dy) + &
                32.0_pr*cos(ky*dy) - 30.0_pr) / dy2) + &
              ((-2.0_pr*cos(2.0_pr*kz*dz) + &
                32.0_pr*cos(kz*dz) - 30.0_pr) / dz2) )
          if (k2==0.0_pr) cycle
          k4 = k2**2
          tmp = tmp + (k2+rho0)/(k4+2.0_pr*rho0*k2)
        end do
      end do
    end do
    
    call MPI_REDUCE(tmp, tot, 1, gpe_mpi_real, MPI_SUM, 0, &
      MPI_COMM_WORLD, ierr)

    if (myrank == 0) then
      temp = (M-n0)/tot
      E0 = (1.0_pr/real(2*V, pr))*(M**2+(M-n0)**2)
      H = E0 + temp*real(V-1, pr)
      temp2 = ((M/(8.0_pr*xr*yr*zr))-(n0/V))/tot
      ! Plot $6/$5 for n0/M for condensed particles.
      open (15, status='unknown', position='append', file='mass.dat')
      write (15, '(9e17.9)') time, im_t, M/(8.0_pr*xr*yr*zr), n0/V, M, n0, &
        temp, temp2, H/V
      close (15)
    end if

    if (save_spectrum) then
      ! Save the spectrum
      call spectrum(a)
    end if
    
    if (save_filter) then
      ! Save a filtered isosurface
      call filtered_surface(a, 0)
    end if
    
    return
  end subroutine condensed_particles
  
! ***************************************************************************  

  subroutine save_norm(time, norm, relnorm)
    ! Save the norm
    use parameters
    implicit none

    real (pr), intent(in) :: time, norm, relnorm

    if (myrank == 0) then
      open (20, status='unknown', position='append', file='norm.dat')
      write (20, '(4e17.9)') time, im_t, norm, relnorm
      close (20)
    end if

    return
  end subroutine save_norm

! ***************************************************************************  

  subroutine save_momentum(time, in_var)
    ! Save the momentum
    use parameters
    use variables, only : momentum
    implicit none

    real (pr), intent(in) :: time
    complex (pr), dimension(0:nx1,js-2:je+2,ks-2:ke+2), intent(in) :: in_var
    real (pr), dimension(3) :: mom

    call momentum(in_var, mom)
    
    if (myrank == 0) then
      open (14, status='unknown', position='append', file='momentum.dat')
      write (14, '(4e17.9)') time, mom(1), mom(2), mom(3)
      close (14)
    end if

    return
  end subroutine save_momentum

! ***************************************************************************  

  subroutine save_surface(in_var)
    ! Save 2D surface data for use in gnuplot.  The data is saved separately on
    ! each process so a shell script must be used to plot it
    use parameters
    use variables
    use ic, only : x, y, z, unit_no
    implicit none

    complex (pr), dimension(0:nx1,js:je,ks:ke), intent(in) :: in_var
    real (pr), dimension(0:nx1,js:je,ks:ke) :: phase, density
    integer :: zpos
    integer :: i, j, k

    ! Get the phase and the density
    call get_phase(in_var, phase)
    call get_density(in_var, density)
    
    zpos = nz/2

    ! Write each process's own data to file, but only if 'zpos' resides on that
    ! particular process
    do k=ks,ke
      if (k==zpos) then
        open (unit_no, status='unknown', file=proc_dir//'psi'//itos(p)//'.dat')
        do i=0,nx1
          write (unit_no, '(6e17.9)') (x(i), y(j), density(i,j,zpos), &
            phase(i,j,zpos), real(in_var(i,j,zpos), pr), &
            aimag(in_var(i,j,zpos)), j=js,je)
          write (unit_no, *)
        end do
        close (unit_no)
        exit
      end if
    end do
    
    return
  end subroutine save_surface
  
! ***************************************************************************  

  subroutine idl_surface(in_var)
    ! Save 3D isosurface data for use in IDL.  As for the gnuplot plots, this
    ! data is saved separately for each process.  It must be read in through
    ! IDL
    use parameters
    use ic, only : unit_no, x, y, z
    use variables, only : get_phase
    implicit none

    complex (pr), dimension(0:nx1,js:je,ks:ke), intent(in) :: in_var
    real (pr), dimension(0:nx1,js:je,ks:ke) :: density, phase
    integer :: i, j, k

    density = abs(in_var)**2
    call get_phase(in_var, phase)

    !call get_minmax(density, 'dens')
    !call get_minmax(phase, 'phase')

    open (unit_no, status='unknown', file=proc_dir//'dens'//itos(p)//'.dat', &
      access='stream')
    
    write (unit_no) t+im_t
    write (unit_no) nx, ny, nz
    write (unit_no) nyprocs, nzprocs
    write (unit_no) js, je, ks, ke
    write (unit_no) in_var
    write (unit_no) x
    write (unit_no) y
    write (unit_no) z

    close (unit_no)

    if (myrank == 0) then
      open (19, status='unknown', position='append', file='p_saved.dat')
      write (19, '(i10)') p
      close (19)
    end if

    return
  end subroutine idl_surface

! ***************************************************************************  
  
  subroutine filtered_surface(a, flag, ind)
    ! Save a filtered 3D isosurface.  High-frequency harmonics are filtered
    use error
    use parameters
    use ic, only : fft, x, y, z, unit_no
    use variables, only : send_recv_z, send_recv_y, pack_y, unpack_y
    implicit none

    integer, intent(in) :: flag
    integer, optional, intent(in) :: ind
    complex (pr), dimension(0:nx1,js:je,ks:ke), intent(inout) :: a
    complex (pr), dimension(0:nx1,js:je,ks:ke) :: filtered
    complex (pr), dimension(0:nx1,js-2:je+2,ks-2:ke+2) :: filtered_tmp
    integer :: i, j, k, ii2, jj2, kk2, k2
    real (pr) :: m

    if (present(ind)) then
      m = fscale*real(ind, pr)
    else
      m = 1.0_pr
    end if
    
    do k=ks,ke
      if (k <= nz1/2+1) then
        kk2 = k**2
      else
        kk2 = (nz1-k+1)**2
      end if
      do j=js,je
        if (j <= ny1/2+1) then
          jj2 = j**2
        else
          jj2 = (ny1-j+1)**2
        end if
        do i=0,nx1
          if (i <= nx1/2+1) then
            ii2 = i**2
          else
            ii2 = (nx1-i+1)**2
          end if
          k2 = ii2 + jj2 + kk2
          !a(i,j,k) = a(i,j,k)*max(1.0_pr-(real(k2, pr)/kc2),0.0_pr)
          !a(i,j,k) = a(i,j,k)*max(1.0_pr-(m*real(k2, pr)/(9.0_pr-1e-3_pr*t)**2),0.0_pr)
          a(i,j,k) = a(i,j,k)*max(1.0_pr-(m*real(k2, pr)/filter_kc**2),0.0_pr)
        end do
      end do
    end do
    
    call fft(a, filtered, 'forward', .true.)
    
    filtered_tmp = 0.0_pr
    filtered_tmp(:,js:je,ks:ke) = filtered
    call send_recv_z(filtered_tmp)
    call pack_y(filtered_tmp)
    call send_recv_y()
    call unpack_y(filtered_tmp)

    ! Save the linelength of a filtered isosurface
    if (save_ll) then
      call save_linelength(filtered_tmp, 1)
    end if
    
    if (save_filter) then
      select case (flag)
        case (0)
          open (unit_no, status='unknown', &
            file=proc_dir//'filtered'//itos(p)//'.dat', access='stream')
          write (unit_no) t
          write (unit_no) nx, ny, nz
          write (unit_no) nyprocs, nzprocs
          write (unit_no) js, je, ks, ke
          write (unit_no) filtered
          write (unit_no) x
          write (unit_no) y
          write (unit_no) z
        case (1)
          open (unit_no, status='unknown', &
            file=proc_dir//'end_state_filtered.dat', access='stream')
          write (unit_no) nx
          write (unit_no) ny
          write (unit_no) nz
          write (unit_no) p
          write (unit_no) t, im_t
          write (unit_no) dt
          write (unit_no) filtered
        case default
          call emergency_stop('ERROR:  Invalid flag (filtered_surface).')
      end select
    
      close (unit_no)

      call get_minmax(abs(filtered)**2, 'filtered')
    end if

    return
  end subroutine filtered_surface

! ***************************************************************************  

  subroutine spectrum(a)
    ! Calculate and save the spectra measurements - mean occupation number,
    ! eta, and integral distribution function, F
    use parameters
    use ic, only : x, y, z, unit_no
    implicit none

    complex (pr), dimension(0:nx1,js:je,ks:ke), intent(in) :: a
    real (pr) :: log2k
    integer :: i, j, k, m, ii2, jj2, kk2, k2, kk
    integer, parameter :: nshells = 7
    real (pr), dimension(nshells) :: eta, tot_eta
    real (pr), dimension(nx/2) :: F, tot_F
    integer, dimension(nshells) :: nharm, tot_nharm

    eta = 0.0_pr
    nharm = 0
    F = 0.0_pr
    
    do k=ks,ke
      if (k <= nz1/2+1) then
        kk2 = k**2
      else
        kk2 = (nz1-k+1)**2
      end if
      do j=js,je
        if (j <= ny1/2+1) then
          jj2 = j**2
        else
          jj2 = (ny1-j+1)**2
        end if
        do i=0,nx1
          if (i <= nx1/2+1) then
            ii2 = i**2
          else
            ii2 = (nx1-i+1)**2
          end if
          k2 = ii2 + jj2 + kk2
          if (sqrt(real(k2, pr)) == 0.0_pr) cycle
          ! Calculate integral distribution function
          do kk=1,nx/2
            if (sqrt(real(k2, pr)) <= real(kk, pr)) then
              F(kk) = F(kk) + abs(a(i,j,k))**2
            end if
          end do
          ! Calculate mean occupation number
          log2k = log( 0.5_pr*sqrt(real(k2, pr))/pi ) / log(2.0_pr)
          do m=1,nshells
            if ((abs(log2k) < real(m, pr)) .and. &
              (abs(log2k) >= real(m-1, pr))) then
              eta(m) = eta(m) + abs(a(i,j,k))**2
              nharm(m) = nharm(m) + 1
              exit
            end if
          end do
        end do
      end do
    end do

    ! Sum measurements onto master process
    call MPI_REDUCE(eta, tot_eta, nshells, gpe_mpi_real, MPI_SUM, 0, &
      MPI_COMM_WORLD, ierr)
    call MPI_REDUCE(nharm, tot_nharm, nshells, MPI_INTEGER, MPI_SUM, 0, &
      MPI_COMM_WORLD, ierr)
    call MPI_REDUCE(F, tot_F, nx/2, gpe_mpi_real, MPI_SUM, 0, &
      MPI_COMM_WORLD, ierr)

    if (myrank == 0) then
      do m=1,nshells
        if (tot_eta(m) == 0.0_pr) cycle
        tot_eta(m) = tot_eta(m)/real(tot_nharm(m), pr)
      end do
    
      ! Write mean occupation number to file
      open (unit_no, file='spectrum/spectrum'//itos(p)//'.dat')
      do m=1,nshells
        write (unit_no, '(2i9,e17.9)') m, tot_nharm(m), tot_eta(m)
      end do
      close (unit_no)

      ! Write integral distribution function to file
      open (unit_no, file='idf/idf'//itos(p)//'.dat')
      do kk=1,nx/2
        write (unit_no, '(i9,e17.9)') kk, tot_F(kk)
      end do
      close (unit_no)

      open (17, status='unknown', position='append', file='eta_time.dat')
      write (17, '(4e17.9)') t, tot_eta(1), tot_eta(2), tot_eta(3)
      close (17)
    end if

    return
  end subroutine spectrum
  
! ***************************************************************************  

  subroutine get_minmax(in_var, var)
    ! Find the minimum and maximum values of a variable over time, and save the
    ! overall maximum to file
    use error
    use parameters
    implicit none

    real (pr), dimension(0:nx1,js:je,ks:ke), intent(in) :: in_var
    real (pr), dimension(2) :: maxs, maxr, mins, minr
    character(*), intent(in) :: var
    integer :: k

    ! maxs/r and mins/r are arrays of length 2 because the MPI functions find
    ! the max/min value as well as its location
    ! Find max/min on each process
    do k=ks,ke
      if (k /= nz/2) cycle
      maxs(1) = maxval(in_var(:,:,nz/2))
      maxs(2) = 0.0_pr
      mins(1) = minval(in_var(:,:,nz/2))
      mins(2) = 0.0_pr
    end do
    
    ! Find max/min over whole array
    call MPI_ALLREDUCE(maxs, maxr, 1, gpe_mpi_2real, MPI_MAXLOC, &
      MPI_COMM_WORLD, ierr)
    call MPI_ALLREDUCE(mins, minr, 1, gpe_mpi_2real, MPI_MINLOC, &
      MPI_COMM_WORLD, ierr)

    ! Update max/min if correct conditions are met
    select case (var)
      case ('dens')
        if (minr(1) < minvar(1)) then
          minvar(1) = minr(1)
        end if

        if (maxr(1) > maxvar(1)) then
          maxvar(1) = maxr(1)
        end if
        
        ! Save current max/min to file
        if (myrank == 0) then
          !print*, 'dens', minvar(1), maxvar(1)
          open (16, file='minmax_'//var//'.dat', access='stream')
          write (16) minvar(1)
          write (16) maxvar(1)
          close (16)
        end if
        
      case ('ave')
        if (minr(1) < minvar(2)) then
          minvar(2) = minr(1)
        end if

        if (maxr(1) > maxvar(2)) then
          maxvar(2) = maxr(1)
        end if
        
        ! Save current max/min to file
        if (myrank == 0) then
          !print*, 'ave', minvar(2), maxvar(2)
          open (16, file='minmax_'//var//'.dat', access='stream')
          write (16) minvar(2)
          write (16) maxvar(2)
          close (16)
        end if
        
      case ('filtered')
        if (minr(1) < minvar(3)) then
          minvar(3) = minr(1)
        end if

        if (maxr(1) > maxvar(3)) then
          maxvar(3) = maxr(1)
        end if
        
        ! Save current max/min to file
        if (myrank == 0) then
          !print*, 'filtered', minvar(3), maxvar(3)
          open (16, file='minmax_'//var//'.dat', access='stream')
          write (16) minvar(3)
          write (16) maxvar(3)
          close (16)
        end if

      case ('phase')
        if (minr(1) < minvar(4)) then
          minvar(4) = minr(1)
        end if

        if (maxr(1) > maxvar(4)) then
          maxvar(4) = maxr(1)
        end if
        
        ! Save current max/min to file
        if (myrank == 0) then
          !print*, 'dens', minvar(1), maxvar(1)
          open (16, file='minmax_'//var//'.dat', access='stream')
          write (16) minvar(4)
          write (16) maxvar(4)
          close (16)
        end if
      case default
        call emergency_stop('ERROR: Unrecognised variable (get_minmax).')
    end select
    
    return
  end subroutine get_minmax
    
! ***************************************************************************  

  subroutine end_state(in_var, flag)
    ! Save variables for use in a restarted run.  Each process saves its own
    ! bit
    use parameters
    use ic, only : fft, unit_no
    implicit none

    integer, intent(in) :: flag
    complex (pr), dimension(0:nx1,js:je,ks:ke), intent(in) :: in_var
    complex (pr), dimension(0:nx1,js:je,ks:ke) :: a
    integer :: j, k

    open (unit_no, file=proc_dir//'end_state.dat', access='stream')

    write (unit_no) nx
    write (unit_no) ny
    write (unit_no) nz
    write (unit_no) p
    write (unit_no) t, im_t
    write (unit_no) dt
    write (unit_no) in_var

    close (unit_no)

    ! Write the variables at the last save
    if (myrank == 0) then
      open (98, file = 'save.dat')
      write (98, *) 'Periodically saved state'
      write (98, *) 't =', t
      write (98, *) 'im_t =', im_t
      write (98, *) 'dt =', dt
      write (98, *) 'nx =', nx
      write (98, *) 'ny =', ny
      write (98, *) 'nz =', nz
      write (98, *) 'p =', p
      close (98)
    end if
    
    ! flag = 1 if the run has been ended
    if (flag == 1) then
      ! Save a final filtered isosurface
      call fft(in_var, a, 'backward', .true.)
      call filtered_surface(a, flag)
      if (myrank == 0) then
        ! Delete RUNNING file to cleanly terminate the run
        open (99, file = 'RUNNING')
        close (99, status = 'delete')
      end if
    end if
    
    return
  end subroutine end_state
  
! ***************************************************************************  

  subroutine get_zeros(in_var)
    ! Find all the zeros of the wavefunction by determining where the real and
    ! imaginary parts simultaneously go to zero.  This routine doesn't find
    ! them all though - get_extra_zeros below finds the rest
    
    ! All the zeros routines are horrible - I'm sure there is a more efficient
    ! way of calculating them
    use parameters
    use ic, only : x, y, z, unit_no
    use variables, only : re_im
    implicit none

    complex (pr), dimension(0:nx1,js-2:je+2,ks-2:ke+2), intent(in) :: in_var
    type (re_im) :: var
    real (pr) :: zero
    real (pr), dimension(0:nx1,js:je,ks:ke) :: denom
    integer :: i, j, k
    !integer, parameter :: z_start=nz/2, z_end=nz/2
    integer :: z_start, z_end

    ! Decide whether to find the zeros over the whole 3D box or just over a 2D
    ! plane
    z_start=ks
    z_end=ke

    allocate(var%re(0:nx1,js-2:je+2,ks-2:ke+2))
    allocate(var%im(0:nx1,js-2:je+2,ks-2:ke+2))
    
    open (unit_no, status='unknown', file=proc_dir//'zeros'//itos(p)//'.dat')
    
    var%re = real(in_var, pr)
    var%im = aimag(in_var)

    write (unit_no, *) "# i,j,k --> i+1,j,k"

    !do k=nz/2+0, nz/2+0
    do k=z_start,z_end
      if ((k==0) .or. (k==nz1)) cycle
      do j=js,je
        if ((j==0) .or. (j==ny1)) cycle
        do i=1,nx1-1
          if (((var%re(i,j,k) == 0.0_pr) .and. &
               (var%im(i,j,k) == 0.0_pr)) .or. &
              ((var%re(i,j,k) == 0.0_pr) .and. &
               (var%im(i,j,k)*var%im(i+1,j,k) < 0.0_pr)) .or. &
              ((var%im(i,j,k) == 0.0_pr) .and. &
               (var%re(i,j,k)*var%re(i+1,j,k) < 0.0_pr)) .or. &
              ((var%re(i,j,k)*var%re(i+1,j,k) < 0.0_pr) .and. &
               (var%im(i,j,k)*var%im(i+1,j,k) < 0.0_pr)) ) then
            denom(i,j,k) = var%re(i,j,k)-var%re(i+1,j,k)
            if (denom(i,j,k) == 0.0_pr) cycle
            zero = -var%re(i+1,j,k)*x(i)/denom(i,j,k) + &
                    var%re(i,j,k)*x(i+1)/denom(i,j,k)
            write (unit_no, '(3e17.9)') zero, y(j), z(k)
          end if
        end do
      end do
    end do
    
    write (unit_no, *) "# i,j,k --> i,j+1,k"

    do k=z_start,z_end
      if ((k==0) .or. (k==nz1)) cycle
      do j=js,je
        if ((j==0) .or. (j==ny1)) cycle
        do i=1,nx1-1
          if (((var%re(i,j,k) == 0.0_pr) .and. &
               (var%im(i,j,k) == 0.0_pr)) .or. &
              ((var%re(i,j,k) == 0.0_pr) .and. &
               (var%im(i,j,k)*var%im(i,j+1,k) < 0.0_pr)) .or. &
              ((var%im(i,j,k) == 0.0_pr) .and. &
               (var%re(i,j,k)*var%re(i,j+1,k) < 0.0_pr)) .or. &
              ((var%re(i,j,k)*var%re(i,j+1,k) < 0.0_pr) .and. &
               (var%im(i,j,k)*var%im(i,j+1,k) < 0.0_pr)) ) then
            denom(i,j,k) = var%re(i,j,k)-var%re(i,j+1,k)
            if (denom(i,j,k) == 0.0_pr) cycle
            zero = -var%re(i,j+1,k)*y(j)/denom(i,j,k) + &
                    var%re(i,j,k)*y(j+1)/denom(i,j,k)
            write (unit_no, '(3e17.9)') x(i), zero, z(k)
          end if
        end do
      end do
    end do
    
    if (z_start /= z_end) then
      write (unit_no, *) "# i,j,k --> i,j,k+1"

      do k=z_start,z_end
        if ((k==0) .or. (k==nz1)) cycle
        do j=js,je
          if ((j==0) .or. (j==ny1)) cycle
          do i=1,nx1-1
            if (((var%re(i,j,k) == 0.0_pr) .and. &
                 (var%im(i,j,k) == 0.0_pr)) .or. &
                ((var%re(i,j,k) == 0.0_pr) .and. &
                 (var%im(i,j,k)*var%im(i,j,k+1) < 0.0_pr)) .or. &
                ((var%im(i,j,k) == 0.0_pr) .and. &
                 (var%re(i,j,k)*var%re(i,j,k+1) < 0.0_pr)) .or. &
                ((var%re(i,j,k)*var%re(i,j,k+1) < 0.0_pr) .and. &
                 (var%im(i,j,k)*var%im(i,j,k+1) < 0.0_pr)) ) then
              denom(i,j,k) = var%re(i,j,k)-var%re(i,j,k+1)
              if (denom(i,j,k) == 0.0_pr) cycle
              zero = -var%re(i,j,k+1)*z(k)/denom(i,j,k) + &
                      var%re(i,j,k)*z(k+1)/denom(i,j,k)
              write (unit_no, '(3e17.9)') x(i), y(j), zero
            end if
          end do
        end do
      end do
    end if

    close (unit_no)

    deallocate(var%re)
    deallocate(var%im)

    return
  end subroutine get_zeros

! ***************************************************************************  

  subroutine get_extra_zeros(in_var)
    ! Find the zeros that the get_zeros routine did not pick up
    use parameters
    use ic, only : x, y, z, unit_no
    use variables, only : re_im
    implicit none

    complex (pr), dimension(0:nx1,js-2:je+2,ks-2:ke+2), intent(in) :: in_var
    type (re_im) :: var
    real (pr), dimension(4) :: zero
    real (pr), dimension(2) :: m
    real (pr), dimension(4,0:nx1,js:je,ks:ke) :: denom
    real (pr) :: xp, yp, zp
    integer :: i, j, k
    !integer, parameter :: z_start=nz/2, z_end=nz/2
    integer :: z_start, z_end

    z_start=ks
    z_end=ke

    allocate(var%re(0:nx1,js-2:je+2,ks-2:ke+2))
    allocate(var%im(0:nx1,js-2:je+2,ks-2:ke+2))

    ! Write these new zeros to the same file as for the get_zeros routine
    open (unit_no, status='old', position='append', &
      file=proc_dir//'zeros'//itos(p)//'.dat')

    var%re = real(in_var, pr)
    var%im = aimag(in_var)
    
    write (unit_no, *) "# i,j,k --> i+1,j,k --> i+1,j+1,k --> i,j+1,k"
    
    do k=z_start,z_end
      if ((k==0) .or. (k==nz1)) cycle
      do j=js,je
        if ((j==0) .or. (j==ny1)) cycle
        do i=1,nx1-1
          if (((var%re(i,j,k)*var%re(i+1,j,k) < 0.0_pr) .and. &
               (var%im(i,j,k)*var%im(i+1,j,k) >= 0.0_pr)) .and. &
              ((var%im(i+1,j,k)*var%im(i+1,j+1,k) < 0.0_pr) .and. &
               (var%re(i+1,j,k)*var%re(i+1,j+1,k) >= 0.0_pr)) .and. &
              ((var%re(i+1,j+1,k)*var%re(i,j+1,k) < 0.0_pr) .and. &
               (var%im(i+1,j+1,k)*var%im(i,j+1,k) >= 0.0_pr)) .and. &
              ((var%im(i,j+1,k)*var%im(i,j,k) < 0.0_pr) .and. &
               (var%re(i,j+1,k)*var%re(i,j,k) >= 0.0_pr)) ) then
            denom(1,i,j,k) = var%re(i,j,k)-var%re(i+1,j,k)
            zero(1) = -var%re(i+1,j,k)*x(i)/denom(1,i,j,k) + &
                       var%re(i,j,k)*x(i+1)/denom(1,i,j,k)
            denom(2,i,j,k) = var%im(i+1,j,k)-var%im(i+1,j+1,k)
            zero(2) = -var%im(i+1,j+1,k)*y(j)/denom(2,i,j,k) + &
                       var%im(i+1,j,k)*y(j+1)/denom(2,i,j,k)
            denom(3,i,j,k) = var%re(i+1,j+1,k)-var%re(i,j+1,k)
            zero(3) = -var%re(i,j+1,k)*x(i+1)/denom(3,i,j,k) + &
                       var%re(i+1,j+1,k)*x(i)/denom(3,i,j,k)
            denom(4,i,j,k) = var%im(i,j+1,k)-var%im(i,j,k)
            zero(4) = -var%im(i,j,k)*y(j+1)/denom(4,i,j,k) + &
                       var%im(i,j+1,k)*y(j)/denom(4,i,j,k)
            m(1) = (y(j)-y(j+1))/(zero(1)-zero(3))
            m(2) = (zero(2)-zero(4))/(x(i+1)-x(i))
            xp = (zero(4)-x(i)*m(2)-y(j)+zero(1)*m(1))/(m(1)-m(2))
            yp = xp*m(1)+y(j)-zero(1)*m(1)
            
            write (unit_no, '(3e17.9)') xp, yp, z(k)
          else if (((var%im(i,j,k)*var%im(i+1,j,k) < 0.0_pr) .and. &
                    (var%re(i,j,k)*var%re(i+1,j,k) >= 0.0_pr)) .and. &
                   ((var%re(i+1,j,k)*var%re(i+1,j+1,k) < 0.0_pr) .and. &
                    (var%im(i+1,j,k)*var%im(i+1,j+1,k) >= 0.0_pr)) .and. &
                   ((var%im(i+1,j+1,k)*var%im(i,j+1,k) < 0.0_pr) .and. &
                    (var%re(i+1,j+1,k)*var%re(i,j+1,k) >= 0.0_pr)) .and. &
                   ((var%re(i,j+1,k)*var%re(i,j,k) < 0.0_pr) .and. &
                    (var%im(i,j+1,k)*var%im(i,j,k) >= 0.0_pr)) ) then
            denom(1,i,j,k) = var%im(i,j,k)-var%im(i+1,j,k)
            zero(1) = -var%im(i+1,j,k)*x(i)/denom(1,i,j,k) + &
                       var%im(i,j,k)*x(i+1)/denom(1,i,j,k)
            denom(2,i,j,k) = var%re(i+1,j,k)-var%re(i+1,j+1,k)
            zero(2) = -var%re(i+1,j+1,k)*y(j)/denom(2,i,j,k) + &
                       var%re(i+1,j,k)*y(j+1)/denom(2,i,j,k)
            denom(3,i,j,k) = var%im(i+1,j+1,k)-var%im(i,j+1,k)
            zero(3) = -var%im(i,j+1,k)*x(i+1)/denom(3,i,j,k) + &
                       var%im(i+1,j+1,k)*x(i)/denom(3,i,j,k)
            denom(4,i,j,k) = var%re(i,j+1,k)-var%re(i,j,k)
            zero(4) = -var%re(i,j,k)*y(j+1)/denom(4,i,j,k) + &
                       var%re(i,j+1,k)*y(j)/denom(4,i,j,k)
            m(1) = (y(j)-y(j+1))/(zero(1)-zero(3))
            m(2) = (zero(2)-zero(4))/(x(i+1)-x(i))
            xp = (zero(4)-x(i)*m(2)-y(j)+zero(1)*m(1))/(m(1)-m(2))
            yp = xp*m(1)+y(j)-zero(1)*m(1)

            write (unit_no, '(3e17.9)') xp, yp, z(k)
          end if
        end do
      end do
    end do
    
    if (z_start /= z_end) then
      write (unit_no, *) "# i,j,k --> i+1,j,k --> i+1,j,k+1 --> i,j,k+1"
      do k=z_start,z_end
        if ((k==0) .or. (k==nz1)) cycle
        do j=js,je
          if ((j==0) .or. (j==ny1)) cycle
          do i=1,nx1-1
            if (((var%re(i,j,k)*var%re(i+1,j,k) < 0.0_pr) .and. &
                 (var%im(i,j,k)*var%im(i+1,j,k) >= 0.0_pr)) .and. &
                ((var%im(i+1,j,k)*var%im(i+1,j,k+1) < 0.0_pr) .and. &
                 (var%re(i+1,j,k)*var%re(i+1,j,k+1) >= 0.0_pr)) .and. &
                ((var%re(i+1,j,k+1)*var%re(i,j,k+1) < 0.0_pr) .and. &
                 (var%im(i+1,j,k+1)*var%im(i,j,k+1) >= 0.0_pr)) .and. &
                ((var%im(i,j,k+1)*var%im(i,j,k) < 0.0_pr) .and. &
                 (var%re(i,j,k+1)*var%re(i,j,k) >= 0.0_pr)) ) then
              denom(1,i,j,k) = var%re(i,j,k)-var%re(i+1,j,k)
              zero(1) = -var%re(i+1,j,k)*x(i)/denom(1,i,j,k) + &
                         var%re(i,j,k)*x(i+1)/denom(1,i,j,k)
              denom(2,i,j,k) = var%im(i+1,j,k)-var%im(i+1,j,k+1)
              zero(2) = -var%im(i+1,j,k+1)*z(k)/denom(2,i,j,k) + &
                         var%im(i+1,j,k)*z(k+1)/denom(2,i,j,k)
              denom(3,i,j,k) = var%re(i+1,j,k+1)-var%re(i,j,k+1)
              zero(3) = -var%re(i,j,k+1)*x(i+1)/denom(3,i,j,k) + &
                         var%re(i+1,j,k+1)*x(i)/denom(3,i,j,k)
              denom(4,i,j,k) = var%im(i,j,k+1)-var%im(i,j,k)
              zero(4) = -var%im(i,j,k)*z(k+1)/denom(4,i,j,k) + &
                         var%im(i,j,k+1)*z(k)/denom(4,i,j,k)
              m(1) = (z(k)-z(k+1))/(zero(1)-zero(3))
              m(2) = (zero(2)-zero(4))/(x(i+1)-x(i))
              xp = (zero(4)-x(i)*m(2)-z(k)+zero(1)*m(1))/(m(1)-m(2))
              zp = xp*m(1)+z(k)-zero(1)*m(1)
              
              write (unit_no, '(3e17.9)') xp, y(j), zp
            else if (((var%im(i,j,k)*var%im(i+1,j,k) < 0.0_pr) .and. &
                      (var%re(i,j,k)*var%re(i+1,j,k) >= 0.0_pr)) .and. &
                     ((var%re(i+1,j,k)*var%re(i+1,j,k+1) < 0.0_pr) .and. &
                      (var%im(i+1,j,k)*var%im(i+1,j,k+1) >= 0.0_pr)) .and. &
                     ((var%im(i+1,j,k+1)*var%im(i,j,k+1) < 0.0_pr) .and. &
                      (var%re(i+1,j,k+1)*var%re(i,j,k+1) >= 0.0_pr)) .and. &
                     ((var%re(i,j,k+1)*var%re(i,j,k) < 0.0_pr) .and. &
                      (var%im(i,j,k+1)*var%im(i,j,k) >= 0.0_pr)) ) then
              denom(1,i,j,k) = var%im(i,j,k)-var%im(i+1,j,k)
              zero(1) = -var%im(i+1,j,k)*x(i)/denom(1,i,j,k) + &
                         var%im(i,j,k)*x(i+1)/denom(1,i,j,k)
              denom(2,i,j,k) = var%re(i+1,j,k)-var%re(i+1,j,k+1)
              zero(2) = -var%re(i+1,j,k+1)*z(k)/denom(2,i,j,k) + &
                         var%re(i+1,j,k)*z(k+1)/denom(2,i,j,k)
              denom(3,i,j,k) = var%im(i+1,j,k+1)-var%im(i,j,k+1)
              zero(3) = -var%im(i,j,k+1)*x(i+1)/denom(3,i,j,k) + &
                         var%im(i+1,j,k+1)*x(i)/denom(3,i,j,k)
              denom(4,i,j,k) = var%re(i,j,k+1)-var%re(i,j,k)
              zero(4) = -var%re(i,j,k)*z(k+1)/denom(4,i,j,k) + &
                         var%re(i,j,k+1)*z(k)/denom(4,i,j,k)
              m(1) = (z(k)-z(k+1))/(zero(1)-zero(3))
              m(2) = (zero(2)-zero(4))/(x(i+1)-x(i))
              xp = (zero(4)-x(i)*m(2)-z(k)+zero(1)*m(1))/(m(1)-m(2))
              zp = xp*m(1)+z(k)-zero(1)*m(1)

              write (unit_no, '(3e17.9)') xp, y(j), zp
            end if
          end do
        end do
      end do
      
      write (unit_no, *) "# i,j,k --> i,j,k+1 --> i,j+1,k+1 --> i,j+1,k"
      do k=z_start,z_end
        if ((k==0) .or. (k==nz1)) cycle
        do j=js,je
          if ((j==0) .or. (j==ny1)) cycle
          do i=1,nx1-1
            if (((var%re(i,j,k)*var%re(i,j,k+1) < 0.0_pr) .and. &
                 (var%im(i,j,k)*var%im(i,j,k+1) >= 0.0_pr)) .and. &
                ((var%im(i,j,k+1)*var%im(i,j+1,k+1) < 0.0_pr) .and. &
                 (var%re(i,j,k+1)*var%re(i,j+1,k+1) >= 0.0_pr)) .and. &
                ((var%re(i,j+1,k+1)*var%re(i,j+1,k) < 0.0_pr) .and. &
                 (var%im(i,j+1,k+1)*var%im(i,j+1,k) >= 0.0_pr)) .and. &
                ((var%im(i,j+1,k)*var%im(i,j,k) < 0.0_pr) .and. &
                 (var%re(i,j+1,k)*var%re(i,j,k) >= 0.0_pr)) ) then
              denom(1,i,j,k) = var%re(i,j,k)-var%re(i,j,k+1)
              zero(1) = -var%re(i,j,k+1)*z(k)/denom(1,i,j,k) + &
                         var%re(i,j,k)*z(k+1)/denom(1,i,j,k)
              denom(2,i,j,k) = var%im(i,j,k+1)-var%im(i,j+1,k+1)
              zero(2) = -var%im(i,j+1,k+1)*y(j)/denom(2,i,j,k) + &
                         var%im(i,j,k+1)*y(j+1)/denom(2,i,j,k)
              denom(3,i,j,k) = var%re(i,j+1,k+1)-var%re(i,j+1,k)
              zero(3) = -var%re(i,j+1,k)*z(k+1)/denom(3,i,j,k) + &
                         var%re(i,j+1,k+1)*z(k)/denom(3,i,j,k)
              denom(4,i,j,k) = var%im(i,j+1,k)-var%im(i,j,k)
              zero(4) = -var%im(i,j,k)*y(j+1)/denom(4,i,j,k) + &
                         var%im(i,j+1,k)*y(j)/denom(4,i,j,k)
              m(1) = (y(j)-y(j+1))/(zero(1)-zero(3))
              m(2) = (zero(2)-zero(4))/(z(k+1)-z(k))
              zp = (zero(4)-z(k)*m(2)-y(j)+zero(1)*m(1))/(m(1)-m(2))
              yp = zp*m(1)+y(j)-zero(1)*m(1)
              
              write (unit_no, '(3e17.9)') x(i), yp, zp
            else if (((var%im(i,j,k)*var%im(i,j,k+1) < 0.0_pr) .and. &
                      (var%re(i,j,k)*var%re(i,j,k+1) >= 0.0_pr)) .and. &
                     ((var%re(i,j,k+1)*var%re(i,j+1,k+1) < 0.0_pr) .and. &
                      (var%im(i,j,k+1)*var%im(i,j+1,k+1) >= 0.0_pr)) .and. &
                     ((var%im(i,j+1,k+1)*var%im(i,j+1,k) < 0.0_pr) .and. &
                      (var%re(i,j+1,k+1)*var%re(i,j+1,k) >= 0.0_pr)) .and. &
                     ((var%re(i,j+1,k)*var%re(i,j,k) < 0.0_pr) .and. &
                      (var%im(i,j+1,k)*var%im(i,j,k) >= 0.0_pr)) ) then
              denom(1,i,j,k) = var%im(i,j,k)-var%im(i,j,k+1)
              zero(1) = -var%im(i,j,k+1)*z(k)/denom(1,i,j,k) + &
                         var%im(i,j,k)*z(k+1)/denom(1,i,j,k)
              denom(2,i,j,k) = var%re(i,j,k+1)-var%re(i,j+1,k+1)
              zero(2) = -var%re(i,j+1,k+1)*y(j)/denom(2,i,j,k) + &
                         var%re(i,j,k+1)*y(j+1)/denom(2,i,j,k)
              denom(3,i,j,k) = var%im(i,j+1,k+1)-var%im(i,j+1,k)
              zero(3) = -var%im(i,j+1,k)*z(k+1)/denom(3,i,j,k) + &
                         var%im(i,j+1,k+1)*z(k)/denom(3,i,j,k)
              denom(4,i,j,k) = var%re(i,j+1,k)-var%re(i,j,k)
              zero(4) = -var%re(i,j,k)*y(j+1)/denom(4,i,j,k) + &
                         var%re(i,j+1,k)*y(j)/denom(4,i,j,k)
              m(1) = (y(j)-y(j+1))/(zero(1)-zero(3))
              m(2) = (zero(2)-zero(4))/(z(k+1)-z(k))
              zp = (zero(4)-z(k)*m(2)-y(j)+zero(1)*m(1))/(m(1)-m(2))
              yp = zp*m(1)+y(j)-zero(1)*m(1)
              
              write (unit_no, '(3e17.9)') x(i), yp, zp
            end if
          end do
        end do
      end do
    end if
  
    close (unit_no)

    return
  end subroutine get_extra_zeros

! ***************************************************************************  

  subroutine get_re_im_zeros(in_var)
    ! Find where the real and imaginary parts separately go to zero
    use parameters
    use ic, only : x, y, z, unit_no
    use variables, only : re_im
    implicit none

    complex (pr), dimension(0:nx1,js-2:je+2,ks-2:ke+2), intent(in) :: in_var
    type (re_im) :: var
    real (pr) :: zero
    real (pr), dimension(0:nx1,js:je,ks:ke) :: denom
    integer :: i, j, k
    !integer, parameter :: z_start=nz/2, z_end=nz/2
    integer :: z_start, z_end

    z_start=ks
    z_end=ke

    allocate(var%re(0:nx1,js-2:je+2,ks-2:ke+2))
    allocate(var%im(0:nx1,js-2:je+2,ks-2:ke+2))

    open (unit_no, status='unknown', &
                   file=proc_dir//'re_zeros'//itos(p)//'.dat')

    var%re = real(in_var, pr)
    var%im = aimag(in_var)

    write (unit_no, *) "# i,j,k --> i+1,j,k"

    do k=z_start,z_end
      if ((k==0) .or. (k==nz1)) cycle
      do j=js,je
        if ((j==0) .or. (j==ny1)) cycle
        do i=1,nx1-1
          if ((var%re(i,j,k) == 0.0_pr) .or. &
              (var%re(i,j,k)*var%re(i+1,j,k) < 0.0_pr)) then
            denom(i,j,k) = var%re(i,j,k)-var%re(i+1,j,k)
            if (denom(i,j,k) == 0.0_pr) cycle
            zero = -var%re(i+1,j,k)*x(i)/denom(i,j,k) + &
                    var%re(i,j,k)*x(i+1)/denom(i,j,k)
            write (unit_no, '(3e17.9)') zero, y(j), z(k)
          end if
        end do
      end do
    end do
    
    write (unit_no, *) "# i,j,k --> i,j+1,k"

    do k=z_start,z_end
      if ((k==0) .or. (k==nz1)) cycle
      do j=js,je
        if ((j==0) .or. (j==ny1)) cycle
        do i=1,nx1-1
          if ((var%re(i,j,k) == 0.0_pr) .or. &
              (var%re(i,j,k)*var%re(i,j+1,k) < 0.0_pr)) then
            denom(i,j,k) = var%re(i,j,k)-var%re(i,j+1,k)
            if (denom(i,j,k) == 0.0_pr) cycle
            zero = -var%re(i,j+1,k)*y(j)/denom(i,j,k) + &
                    var%re(i,j,k)*y(j+1)/denom(i,j,k)
            write (unit_no, '(3e17.9)') x(i), zero, z(k)
          end if
        end do
      end do
    end do
    
    if (z_start /= z_end) then
      write (unit_no, *) "# i,j,k --> i,j,k+1"

      do k=z_start,z_end
        if ((k==0) .or. (k==nz1)) cycle
        do j=js,je
          if ((j==0) .or. (j==ny1)) cycle
          do i=1,nx1-1
            if ((var%re(i,j,k) == 0.0_pr) .and. &
                (var%re(i,j,k)*var%re(i,j,k+1) < 0.0_pr)) then
              denom(i,j,k) = var%re(i,j,k)-var%re(i,j,k+1)
              if (denom(i,j,k) == 0.0_pr) cycle
              zero = -var%re(i,j,k+1)*z(k)/denom(i,j,k) + &
                      var%re(i,j,k)*z(k+1)/denom(i,j,k)
              write (unit_no, '(3e17.9)') x(i), y(j), zero
            end if
          end do
        end do
      end do
    end if

    close (unit_no)

    ! Barrier here to make sure some processes don't try to open the new file
    ! without it having been previously closed
    call MPI_BARRIER(MPI_COMM_WORLD, ierr)
    
    open (unit_no, status='unknown', &
                   file=proc_dir//'im_zeros'//itos(p)//'.dat')
                      
    write (unit_no, *) "# i,j,k --> i+1,j,k"
    
    do k=z_start,z_end
      if ((k==0) .or. (k==nz1)) cycle
      do j=js,je
        if ((j==0) .or. (j==ny1)) cycle
        do i=1,nx1-1
          if ((var%im(i,j,k) == 0.0_pr) .or. &
              (var%im(i,j,k)*var%im(i+1,j,k) < 0.0_pr)) then
            denom(i,j,k) = var%im(i,j,k)-var%im(i+1,j,k)
            if (denom(i,j,k) == 0.0_pr) cycle
            zero = -var%im(i+1,j,k)*x(i)/denom(i,j,k) + &
                    var%im(i,j,k)*x(i+1)/denom(i,j,k)
            write (unit_no, '(3e17.9)') zero, y(j), z(k)
          end if
        end do
      end do
    end do
    
    write (unit_no, *) "# i,j,k --> i,j+1,k"

    do k=z_start,z_end
      if ((k==0) .or. (k==nz1)) cycle
      do j=js,je
        if ((j==0) .or. (j==ny1)) cycle
        do i=1,nx1-1
          if ((var%im(i,j,k) == 0.0_pr) .or. &
              (var%im(i,j,k)*var%im(i,j+1,k) < 0.0_pr)) then
            denom(i,j,k) = var%im(i,j,k)-var%im(i,j+1,k)
            if (denom(i,j,k) == 0.0_pr) cycle
            zero = -var%im(i,j+1,k)*y(j)/denom(i,j,k) + &
                    var%im(i,j,k)*y(j+1)/denom(i,j,k)
            write (unit_no, '(3e17.9)') x(i), zero, z(k)
          end if
        end do
      end do
    end do
    
    if (z_start /= z_end) then
      write (unit_no, *) "# i,j,k --> i,j,k+1"

      do k=z_start,z_end
      if ((k==0) .or. (k==nz1)) cycle
        do j=js,je
        if ((j==0) .or. (j==ny1)) cycle
          do i=1,nx1-1
            if ((var%im(i,j,k) == 0.0_pr) .and. &
                (var%im(i,j,k)*var%im(i,j,k+1) < 0.0_pr)) then
              denom(i,j,k) = var%im(i,j,k)-var%im(i,j,k+1)
              if (denom(i,j,k) == 0.0_pr) cycle
              zero = -var%im(i,j,k+1)*z(k)/denom(i,j,k) + &
                      var%im(i,j,k)*z(k+1)/denom(i,j,k)
              write (unit_no, '(3e17.9)') x(i), y(j), zero
            end if
          end do
        end do
      end do
    end if

    close (unit_no)

    return
  end subroutine get_re_im_zeros
  
! ***************************************************************************  

  subroutine save_linelength(in_var, flag)
    ! Save the total vortex line length
    use parameters
    use variables, only : linelength
    implicit none

    complex (pr), dimension(0:nx1,js-2:je+2,ks-2:ke+2), intent(in) :: in_var
    integer :: flag
    real (pr) :: tmp, length

    ! Get the line length on each individual process
    tmp = linelength(t, in_var)

    ! Sum the line length over all processes and send it to process 0
    call MPI_REDUCE(tmp, length, 1, gpe_mpi_real, MPI_SUM, 0, &
      MPI_COMM_WORLD, ierr) 

    if (myrank == 0) then
      if (flag == 0) then
        ! Write the unfiltered line length
        open (13, status='unknown', position='append', file='linelength.dat')
        write (13, '(3e17.9)') t, im_t, length
        close (13)
      else if (flag == 1) then
        ! Write the filtered line length
        open (18, status='unknown', position='append', file='filtered_ll.dat')
        write (18, '(3e17.9)') t, im_t, length
        close (18)
      end if
    end if

    return
  end subroutine save_linelength

! ***************************************************************************  

  subroutine diag(old2, old, new)
    use parameters
    use variables
    use ic, only : x, y, z, unit_no
    implicit none
    
    complex (pr), dimension(0:nx1,js-2:je+2,ks-2:ke+2), intent(in) :: old, old2
    complex (pr), dimension(0:nx1,js:je,ks:ke), intent(in) :: new
    complex (pr), dimension(0:nx1,js:je,ks:ke) :: lhs, rhs
    integer :: zpos
    integer :: i, j, k
    
    lhs = 0.5_pr*(new-old2(:,js:je,ks:ke))/dt
    
    rhs = 0.5_pr*(eye+0.01_pr) * ( laplacian(old) + &
      (1.0_pr-abs(old(:,js:je,ks:ke))**2)*old(:,js:je,ks:ke) )

    zpos = nz/2

    do k=ks,ke
      if (k==zpos) then
        open (unit_no, status='unknown', file=proc_dir//'diag'//itos(p)//'.dat')
        do i=0,nx1
          write (unit_no, '(3e17.9)') (x(i), y(j), &
            abs(rhs(i,j,zpos)-lhs(i,j,zpos)), j=js,je)
          write (unit_no, *)
        end do
        close (unit_no)
        exit
      end if
    end do

    return
  end subroutine diag
    
! ***************************************************************************  

  subroutine average(in_var)
    ! Save time-averaged data
    use parameters
    use ic, only : x, y, z, unit_no
    implicit none

    complex (pr), dimension(0:nx1,js:je,ks:ke), intent(in) :: in_var
    integer :: j, k

    ave = ave + abs(in_var)**2
    
    open (unit_no, status='unknown', file=proc_dir//'ave'//itos(p)//'.dat', &
      access='stream')

    write (unit_no) t
    write (unit_no) nx, ny, nz
    write (unit_no) nyprocs, nzprocs
    write (unit_no) js, je, ks, ke
    write (unit_no) ave / real(snapshots, pr)
    write (unit_no) x
    write (unit_no) y
    write (unit_no) z

    close (unit_no)

    call get_minmax(ave / real(snapshots, pr), 'ave')

    snapshots = snapshots+1

    return
  end subroutine average

! ***************************************************************************  

  subroutine pp_save_filter()
    ! Save a series of filtered isosurfaces after a run has been completed
    use parameters
    use ic, only : x, y, z, fft, unit_no
    implicit none

    complex (pr), dimension(0:nx1,js:je,ks:ke) :: in_var, a
    integer :: i, j, dummy_int

    do j=1,nfilter
      if (myrank == 0) then
        open (50, file='p_saved.dat')
        open (22, status='unknown', position='append', file='filtered_ll.dat')
        write (22, *) '# ', j
        close (22)
      end if
      do i=1,nlines
        if (myrank == 0) then
          read (50, *) p
        end if
        
        call MPI_BCAST(p, 1, MPI_INTEGER, 0, MPI_COMM_WORLD, ierr)

        open (unit_no, file=proc_dir//'dens'//itos(p)//'.dat', &
          access='stream')

        read (unit_no) t
        read (unit_no) dummy_int, dummy_int, dummy_int
        read (unit_no) dummy_int, dummy_int
        read (unit_no) dummy_int, dummy_int, dummy_int, dummy_int
        read (unit_no) in_var
        read (unit_no) x
        read (unit_no) y
        read (unit_no) z
        
        call fft(in_var, a, 'backward', .true.)
        
        call filtered_surface(a, 0, j)
      end do
      if (myrank == 0) then
        open (22, status='unknown', position='append', file='filtered_ll.dat')
        write (22, *)
        write (22, *)
        close (22)
        close (50)
      end if
    end do

    return
  end subroutine pp_save_filter

! ***************************************************************************  

  subroutine save_run(in_var)
    ! Save 3D isosurfaces if the file SAVE exists in the run directory.
    use parameters
    implicit none

    complex (pr), dimension(0:nx1,js:je,ks:ke), intent(in) :: in_var
    logical :: save_exist
    integer :: save3d

    save3d = 0

    if (myrank == 0) then
      inquire (file='SAVE', exist=save_exist)
      if (save_exist) then
        save3d = 1
      end if
    end if

    call MPI_BCAST(save3d, 1, MPI_INTEGER, 0, MPI_COMM_WORLD, ierr)
    
    if (save3d == 1) then
      call idl_surface(in_var)
      if (myrank == 0) then
        open (95, file='SAVE')
        close (95, status='delete')
      end if
    end if

    return
  end subroutine save_run

! ***************************************************************************  

  subroutine print_runtime_info()
    use error, only : emergency_stop
    use parameters
    implicit none

    if (myrank == 0) then
      select case (scheme)
        case ('euler')
          print*, 'Explicit Euler time stepping'
        case ('rk2')
          print*, 'Explicit second order Runge-Kutta time stepping'
        case ('rk4')
          print*, 'Explicit fourth order Runge-Kutta time stepping'
        case ('rk45')
          print*, 'Explicit fifth order &
                  &Runge-Kutta-Fehlberg adaptive time stepping'
        case default
          call emergency_stop('ERROR: Unrecognised time stepping scheme.')
      end select
    end if

    if (myrank == 0) then
      select case (eqn_to_solve)
        case (1)
          print*, 'Homogeneous condensate, natural units non-dim.'
          print*, '-2i*dpsi/dt + 2iU*dpsi/dx = del^2(psi) + (1-|psi|^2)psi'
        case (2)
          print*, 'Homogeneous condensate, no mu.'
          print*, 'i*dpsi/dt = -del^2(psi) + |psi|^2*psi'
        case (3)
          print*, 'Solving CASE 3'
        case (4)
          print*, 'Trapped condensate, harmonic oscillator units non-dim.'
          print*, 'i*dpsi/dt = -0.5_pr*del^2(psi) + Vtrap*psi + g(|psi|^2)psi -&
            &mu*psi'
      end select
    end if
  
    return
  end subroutine print_runtime_info
  
end module io
