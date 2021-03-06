subroutine SHMultiTaperMaskCSE(mtse, sd, cilm1, lmax1, cilm2, lmax2, tapers, &
                               lmaxt, K, taper_wt, norm, csphase, exitstatus)
!------------------------------------------------------------------------------
!
!   This subroutine will calculate the multitaper cross-spectrum estimate
!   utilizing the first K localization windows of an arbitrarily shaped window.
!   The matrix TAPERS contains the spherical-harmonic coefficients of the
!   windows in packed form according to the conventions used by SHCilmToVector.
!   The standard error is calculated using an unbiased estimate of the sample
!   variance.
!
!   Calling Parameters
!
!       IN
!           cilm1       Input spherical harmonic file.
!           lmax1       Maximum degree of cilm1.
!           cilm2       Input spherical harmonic file.
!           lmax2       Maximum degree of cilm2.
!           tapers      The eigenvector matrix returned from a program
!                       such as SHReturnTapersMap, where each column
!                       corresponds to the spherical-harmonic coefficients of
!                       a window in the packed form used by SHCilmToVector.
!           lmaxt       Maximum degree of the eigentapers.
!           K           Number of tapers to use in the multitaper spectral
!                       estimation.
!
!       OUT
!           mtse        Multitaper spectrum estimate, valid up to and including
!                       a maximum degree lmax-lmaxt.
!           sd          Standard error of the multitaper spectrum estimate.
!
!       OPTIONAL (IN)
!           taper_wt    Weight to be applied to each direct spectral estimate.
!                       This should sum to unity.
!           csphase:    1: Do not include the phase factor of (-1)^m (default).
!                       -1: Apply the phase factor of (-1)^m.
!           norm:       Normalization to be used when calculating Legendre
!                       functions
!                           (1) "geodesy" (default)
!                           (2) Schmidt
!                           (3) unnormalized
!                           (4) orthonormalized
!
!       OPTIONAL (OUT)
!           exitstatus  If present, instead of executing a STOP when an error
!                       is encountered, the variable exitstatus will be
!                       returned describing the error.
!                       0 = No errors;
!                       1 = Improper dimensions of input array;
!                       2 = Improper bounds for input variable;
!                       3 = Error allocating memory;
!                       4 = File IO error.
!
!   Copyright (c) 2005-2019, SHTOOLS
!   All rights reserved.
!
!------------------------------------------------------------------------------
    use SHTOOLS, only:  SHCrossPowerSpectrum, SHVectorToCilm, MakeGridGLQ, &
                        SHGLQ, SHExpandGLQ
    use ftypes

    implicit none

    real(dp), intent(out) :: mtse(:), sd(:)
    real(dp), intent(in) :: cilm1(:,:,:), cilm2(:,:,:), tapers(:,:)
    integer(int32), intent(in) :: lmax1, lmax2, lmaxt, K
    real(dp), intent(in), optional :: taper_wt(:)
    integer(int32), intent(in), optional :: csphase, norm
    integer(int32), intent(out), optional :: exitstatus
    integer(int32) :: i, l, lmax, phase, mnorm, astat(9), lmaxmul, nlat, nlong
    real(dp), allocatable, save :: zero(:), w(:)
    integer(int32), save :: first = 1, lmaxmul_last = -1
    real(dp) :: se(lmax1-lmaxt+1,K), pi, factor
    real(dp), allocatable :: shwin(:,:,:), shloc1(:,:,:),  shloc2(:,:,:), &
                             grid1glq(:,:), grid2glq(:,:), gridwinglq(:,:), &
                             temp(:,:)

!$OMP   threadprivate(zero, w, first, lmaxmul_last)

    if (present(exitstatus)) exitstatus = 0

    pi = acos(-1.0_dp)

    lmax = min(lmax1, lmax2)

    if (size(cilm1(:,1,1)) < 2 .or. size(cilm1(1,:,1)) < lmax+1 .or. &
        size(cilm1(1,1,:)) < lmax+1) then
        print*, "Error --- SHMultiTaperCSE"
        print*, "CILM1 must be dimensioned (2,LMAX+1, LMAX+1) " // &
                "where LMAX is ", lmax
        print*, "Input array is dimensioned ", size(cilm1(:,1,1)), &
                size(cilm1(1,:,1)), size(cilm1(1,1,:))
        if (present(exitstatus)) then
            exitstatus = 1
            return
        else
            stop
        end if

    else if (size(cilm2(:,1,1)) < 2 .or. size(cilm2(1,:,1)) < lmax+1 .or. &
             size(cilm2(1,1,:)) < lmax+1) then
        print*, "Error --- SHMultiTaperCSE"
        print*, "CILM2 must be dimensioned (2,LMAX+1, LMAX+1) " // &
                "where lmax is ", lmax
        print*, "Input array is dimensioned ", size(cilm2(:,1,1)), &
                size(cilm2(1,:,1)), size(cilm2(1,1,:))
        if (present(exitstatus)) then
            exitstatus = 1
            return
        else
            stop
        end if

    else if (size(tapers(:,1)) < (lmaxt+1)**2 .or. size(tapers(1,:)) < K) then
        print*, "Error --- SHMultiTaperCSE"
        print*, "TAPERS must be dimensioned ((LMAXT+1)**2, K) " // &
                "where LMAXT and K are, ", lmaxt, K
        print*, "Input array is dimensioned ", size(tapers(:,1)), &
                size(tapers(1,:))
        if (present(exitstatus)) then
            exitstatus = 1
            return
        else
            stop
        end if

    else if (size(mtse) < lmax-lmaxt+1) then
        print*, "Error --- SHMultiTaperCSE"
        print*, "MTSE must be dimensioned as (LMAX-LMAXT+1) " // &
                "where LMAX and LMAXT are ", lmax, lmaxt
        print*, "Input dimension of array is ", size(mtse)
        if (present(exitstatus)) then
            exitstatus = 1
            return
        else
            stop
        end if

    else if (size(sd) < lmax-lmaxt+1) then
        print*, "Error --- SHMultiTaperCSE"
        print*, "SD must be dimensioned as (LMAX-LMAXT1) where " // &
                "LMAX and LMAXT are ", lmax, lmaxt
        print*, "Input dimension of array is ", size(sd)
        if (present(exitstatus)) then
            exitstatus = 1
            return
        else
            stop
        end if

    else if (lmax < lmaxt) then
        print*, "Error --- SHMultiTaperCSE"
        print*, "LMAX must be larger than LMAXT."
        print*, "Input valuse of LMAX and LMAXT are ", lmax, lmaxt
        if (present(exitstatus)) then
            exitstatus = 2
            return
        else
            stop
        end if

    end if

    if (present(taper_wt)) then
        if (size(taper_wt) < K) then
            print*, "Error --- SHMultiTaperCSE"
            print*, "TAPER_WT must be dimensioned as (K) where K is ", K
            print*, "Input dimension of array is ", size(taper_wt)
            if (present(exitstatus)) then
                exitstatus = 1
                return
            else
                stop
            end if

        end if
    end if

    if (present(norm)) then
        if (norm > 4 .or. norm < 1) then
            print*, "Error --- SHMultiTaperCSE"
            print*, "Parameter NORM must be 1 (geodesy), 2 (Schmidt), " // &
                    "3 (unnormalized), or 4 (orthonormalized)."
            print*, "Input value is ", norm
            if (present(exitstatus)) then
                exitstatus = 2
                return
            else
                stop
            end if

        end if
        mnorm = norm

    else
        mnorm = 1

    end if

    if (present(csphase)) then
        if (csphase /= -1 .and. csphase /= 1) then
            print*, "Error --- SHMultiTaperCSE"
            print*, "CSPHASE must be 1 (exclude) or -1 (include)."
            print*, "Input value is ", csphase
            if (present(exitstatus)) then
                exitstatus = 2
                return
            else
                stop
            end if

        else
            phase = csphase

        end if
    else
        phase = 1

    end if


    lmaxmul = lmax + lmaxt
    nlat = lmax + lmaxt + 1
    nlong = 2 * (lmax + lmaxt) + 1

    allocate (shwin(2,lmaxt+1,lmaxt+1), stat = astat(1))
    allocate (shloc1(2, lmax1+lmaxt+1, lmax1+lmaxt+1), stat= astat(2))
    allocate (shloc2(2, lmax2+lmaxt+1, lmax2+lmaxt+1), stat = astat(3))
    allocate (grid1glq(nlat,nlong), stat = astat(4))
    allocate (grid2glq(nlat,nlong), stat = astat(5))
    allocate (gridwinglq(nlat,nlong), stat = astat(6))
    allocate (temp(nlat,nlong), stat = astat(7))

    if (sum(astat(1:7)) /= 0) then
        print*, "Error --- SHMultiTaperCSE"
        print*, "Problem allocating arrays SHWIN, SHLOC1, " // &
                "SHLOC2, GRID1GLQ, GRID2GLQ, GRIDWNGLQ, " // &
                "and TEMP", astat(1), astat(2), astat(3), &
                astat(4), astat(5), astat(6), astat(7)
        if (present(exitstatus)) then
            exitstatus = 3
            return
        else
            stop
        end if

    end if

   if (first == 1) then
        first = 0
        lmaxmul_last = lmaxmul

        allocate (zero(lmaxmul+1), stat = astat(1))
        allocate (w(lmaxmul+1), stat = astat(2))

        if (sum(astat(1:2)) /= 0) then
            print*, "Error --- SHMultiTaperCSE"
            print*, "Problem allocating arrays ZERO and W", astat(1), astat(2)
            if (present(exitstatus)) then
                exitstatus = 3
                return
            else
                stop
            end if

        end if

        if (present(exitstatus)) then
            call SHGLQ(lmaxmul, zero, w, csphase = phase, norm = mnorm, &
                       exitstatus = exitstatus)
            if (exitstatus /= 0) return
        else
            call SHGLQ(lmaxmul, zero, w, csphase = phase, norm = mnorm)
        end if

    end if

    if (lmaxmul /= lmaxmul_last) then
        lmaxmul_last = lmaxmul

        deallocate (zero)
        deallocate (w)
        allocate (zero(lmaxmul+1), stat = astat(1))
        allocate (w(lmaxmul+1), stat = astat(2))

        if (sum(astat(1:2)) /= 0) then
            print*, "Error --- SHMultiTaperCSE"
            print*, "Problem allocating arrays ZERO and W", astat(1), astat(2)
            if (present(exitstatus)) then
                exitstatus = 3
                return
            else
                stop
            end if

        end if

        if (present(exitstatus)) then
            call SHGLQ(lmaxmul, zero, w, csphase = phase, norm = mnorm, &
                       exitstatus = exitstatus)
            if (exitstatus /= 0) return
        else
            call SHGLQ(lmaxmul, zero, w, csphase = phase, norm = mnorm)
        end if

    end if

    mtse = 0.0_dp
    sd = 0.0_dp

    !--------------------------------------------------------------------------
    !
    !   Calculate localized power spectra
    !
    !--------------------------------------------------------------------------

    if (present(exitstatus)) then
        call MakeGridGLQ(grid1glq, cilm1(1:2,1:lmax+1, 1:lmax+1), &
                         lmaxmul, zero = zero, csphase = phase, norm = mnorm, &
                         exitstatus = exitstatus)
        if (exitstatus /= 0) return
        call MakeGridGLQ(grid2glq, cilm2(1:2,1:lmax+1, 1:lmax+1), &
                         lmaxmul, zero = zero, csphase = phase, norm = mnorm, &
                         exitstatus = exitstatus)
        if (exitstatus /= 0) return

    else
        call MakeGridGLQ(grid1glq, cilm1(1:2,1:lmax+1, 1:lmax+1), &
                         lmaxmul, zero = zero, csphase = phase, norm = mnorm)
        call MakeGridGLQ(grid2glq, cilm2(1:2,1:lmax+1, 1:lmax+1), &
                         lmaxmul, zero = zero, csphase = phase, norm = mnorm)

    end if

    do i = 1, K
        shwin = 0.0_dp

        if (present(exitstatus)) then
            call SHVectorToCilm(tapers(:,i), shwin, lmaxt, &
                                exitstatus = exitstatus)
            if (exitstatus /= 0) return
            call MakeGridGLQ(gridwinglq, shwin(1:2,1:lmaxt+1, 1:lmaxt+1), &
                             lmaxmul, zero = zero, csphase = phase, &
                             norm = mnorm, exitstatus = exitstatus)
            if (exitstatus /= 0) return
            temp(1:nlat,1:nlong) = grid1glq(1:nlat,1:nlong) &
                                   * gridwinglq(1:nlat,1:nlong)
            call SHExpandGLQ(shloc1, lmaxmul, temp, w, zero = zero, &
                             csphase = phase, norm = mnorm, &
                             exitstatus = exitstatus)
            if (exitstatus /= 0) return
            temp(1:nlat,1:nlong) = grid2glq(1:nlat,1:nlong) &
                                   * gridwinglq(1:nlat,1:nlong)
            call SHExpandGLQ(shloc2, lmaxmul, temp, w, zero = zero, &
                             csphase = phase, norm = mnorm, &
                             exitstatus = exitstatus)
            if (exitstatus /= 0) return
            call SHCrossPowerSpectrum(shloc1, shloc2, lmax-lmaxt, se(:,i), &
                                      exitstatus = exitstatus)
            if (exitstatus /= 0) return

        else
            call SHVectorToCilm(tapers(:,i), shwin, lmaxt)
            call MakeGridGLQ(gridwinglq, shwin(1:2,1:lmaxt+1, 1:lmaxt+1), &
                             lmaxmul, zero = zero, csphase = phase,&
                             norm = mnorm)
            temp(1:nlat,1:nlong) = grid1glq(1:nlat,1:nlong) &
                                   * gridwinglq(1:nlat,1:nlong)
            call SHExpandGLQ(shloc1, lmaxmul, temp, w, zero = zero, &
                             csphase = phase, norm = mnorm)
            temp(1:nlat,1:nlong) = grid2glq(1:nlat,1:nlong) &
                                   * gridwinglq(1:nlat,1:nlong)
            call SHExpandGLQ(shloc2, lmaxmul, temp, w, zero = zero, &
                             csphase = phase, norm = mnorm)
            call SHCrossPowerSpectrum(shloc1, shloc2, lmax-lmaxt, se(:,i))

        end if

    end do

    if (present(taper_wt)) then

        factor = sum(taper_wt(1:K))**2 - sum(taper_wt(1:K)**2)
        factor = factor * sum(taper_wt(1:K))
        factor = sum(taper_wt(1:K)**2) / factor
    
        do l = 0, lmax-lmaxt, 1
            mtse(l+1) = dot_product(se(l+1,1:K), taper_wt(1:K)) / &
                        sum(taper_wt(1:K))

            if (K > 1) then
                sd(l+1) = dot_product( (se(l+1,1:K) - mtse(l+1) )**2, &
                                       taper_wt(1:K) ) * factor
            end if

        end do

    else
        do l = 0, lmax-lmaxt, 1
            mtse(l+1) = sum(se(l+1,1:K)) / dble(K)

            if (K > 1) then
                sd(l+1) = sum( ( se(l+1,1:K) - mtse(l+1) )**2 ) / dble(K-1) &
                          / dble(K)  ! standard error !
            end if

        end do

    end if

    if (K > 1) sd(1:lmax-lmaxt+1) = sqrt(sd(1:lmax-lmaxt+1) )

    deallocate (shwin)
    deallocate (shloc1)
    deallocate (shloc2)
    deallocate (grid1glq)
    deallocate (grid2glq)
    deallocate (gridwinglq)
    deallocate (temp)

end subroutine SHMultiTaperMaskCSE
