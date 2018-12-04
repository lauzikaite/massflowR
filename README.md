
massflowR
=========

Package for pre-processing of high-resolution, untargeted, centroid LC-MS data.

Overview
========

`massFlowR` detects and aligns structurally-related spectral peaks across LC-MS experiment samples. Its pipeline consists of three stages:

Individual samples processing
-----------------------------

Each LC-MS file in the experiment is processed independently.

-   Chromatographic peak detection enabled by the *centWave* algorithm from `xcms` package.

-   Grouping of chromatographic peaks into structurally-related sets of peaks, or, Pseudo-Chemical-Spectra (see [Peak Grouping](http://htmlpreview.github.io/?https://github.com/lauzikaite/massFlowR/blob/master/inst/doc/massFlowR.html)).

Individual samples can be processed in real-time during LC-MS spectra acquisition, or in parallel, using backend provided by `doParallel` package.

Alignment
---------

To align peaks across all samples in the LC-MS experiment, an algorithm, which compares the overall similarity of structurally-related groups of peaks is implemented (see [Peak alignment](http://htmlpreview.github.io/?https://github.com/lauzikaite/massFlowR/blob/master/inst/doc/massFlowR.html)).

Alignment validation and peak filling
-------------------------------------

*(under development)*

Once samples are aligned, the obtained peak groups are validated. Intensity values for each peak in a group are correlated across all samples. Correlation estimates are then used to build networks of peaks, that behave similarly across all samples. Peaks exhibiting a different pattern in their intensities are put into a new peak-group.

Finally, for samples, in which a peak from a validated peak-group was not detected, peak-filling is performed. Intensity data is obtained for each missing peak using original LC-MS files. In contrast to `xcms` package, *mz* and *rt* values for intensity integration are estimated for each sample separetely. *mz* and *rt* values are taken from two surrounding samples, in which the peak-of-interest was present, and extrapolated.

If in-house chemical reference database is available, final validated peak-groups are annotated (see [Peak annotation](http://htmlpreview.github.io/?https://github.com/lauzikaite/massFlowR/blob/master/inst/doc/massFlowR.html)).

Installation
============

``` r
# For devel version
devtools::install_github("lauzikaite/massflowR")
```
