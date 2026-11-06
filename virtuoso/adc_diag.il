;; adc_diag.il -- "ADC Diag" menu for the Virtuoso CIW
;;
;; Takes the ADC output from a finished transient simulation, samples it,
;; writes a copy of the ADC Output Diagnosis page with the data built in,
;; and opens it in a web browser.
;;
;; Install (once per session, or put the line in ~/.cdsinit):
;;   load("/path/to/adc-output-diagnosis/virtuoso/adc_diag.il")
;; An "ADC Diag" menu then appears in the CIW menu bar.
;;
;; The three settings below can be changed before or after loading, e.g. in the CIW:
;;   adcDiagBrowser = "firefox"

;; ---------- settings ----------
unless(boundp('adcDiagToolHtml)
  adcDiagToolHtml = strcat(getShellEnvVar("HOME") "/adc-output-diagnosis/index.html"))  ; path of index.html
unless(boundp('adcDiagBrowser)
  adcDiagBrowser = "google-chrome")   ; browser command; falls back to firefox, then xdg-open
unless(boundp('adcDiagOutDir)
  adcDiagOutDir = "/tmp")       ; where the generated pages are written

;; values shown in the form (the last ones used are remembered)
unless(boundp('adcDiagLast)
  adcDiagLast = list(nil 'psf "" 'net "/DOUT" 'fs 6.4e9 't0 10e-9 'n 32768 'bits 10 'm 1))

;; ---------- helpers ----------
procedure(adcDiagOpenPage(file)
  ;; open file in adcDiagBrowser; if that command is missing, try firefox, then xdg-open
  system(sprintf(nil "( %s '%s' || firefox '%s' || xdg-open '%s' ) >/dev/null 2>&1 &"
                 adcDiagBrowser file file file))
)

procedure(adcDiagGuessPsf()
  ;; results directory of the current ADE session, if there is one (falls back to "")
  let((s d)
    s = car(errset(asiGetCurrentSession() nil))
    when(s d = car(errset(asiGetResultsDir(s) nil)))
    if(stringp(d) then d else "")
  )
)

procedure(adcDiagOpenTool()
  unless(isFile(adcDiagToolHtml)
    error("ADC Diag: cannot find %s. Set adcDiagToolHtml to the path of index.html.\n" adcDiagToolHtml))
  adcDiagOpenPage(adcDiagToolHtml)
)

;; copy index.html to htmlFile, putting the sampled data where the page has its ADC-DATA-HERE marker line
procedure(adcDiagWriteHtml(htmlFile wave o)
  let((in out line ts v i)
    in = infile(adcDiagToolHtml)
    unless(in error("ADC Diag: cannot read %s\n" adcDiagToolHtml))
    out = outfile(htmlFile "w")
    unless(out close(in) error("ADC Diag: cannot write %s\n" htmlFile))
    ts = 1.0 / o->fs
    while(gets(line in)
      if(rexMatchp("ADC-DATA-HERE" line) then
        fprintf(out "<script>window.ADC_PRELOAD={source:\"%s  %s\",fs:\"%g\",bits:\"%d\",m:\"%d\",data:["
                o->net o->psf o->fs o->bits o->m)
        for(i 0 o->n - 1
          v = value(wave o->t0 + i * ts)
          fprintf(out "%s%.9g" if(i > 0 "," "") float(v))
          when(mod(i 16) == 15 fprintf(out "\n"))
        )
        fprintf(out "]};</script>\n")
      else
        fprintf(out "%s" line)
      )
    )
    close(in)
    close(out)
  )
)

procedure(adcDiagRun(o)
  let((wave tLast tag htmlFile)
    unless(isFile(adcDiagToolHtml)
      error("ADC Diag: cannot find %s. Set adcDiagToolHtml to the path of index.html.\n" adcDiagToolHtml))
    unless(car(errset(openResults(o->psf) nil))
      error("ADC Diag: cannot open results directory %s\n" o->psf))
    unless(errset(selectResult('tran) nil)
      error("ADC Diag: no transient results in %s\n" o->psf))
    wave = car(errset(VT(o->net) nil))
    unless(wave error("ADC Diag: signal %s not found in the transient results\n" o->net))
    tLast = o->t0 + (o->n - 1) / o->fs
    unless(numberp(car(errset(value(wave tLast) nil)))
      error("ADC Diag: the transient run must reach t0 + (N-1)/Fs = %g s\n" tLast))
    tag = rexReplace(getCurrentTime() "[^0-9A-Za-z]" "_" 0)
    htmlFile = sprintf(nil "%s/adc_diag_%s.html" adcDiagOutDir tag)
    adcDiagWriteHtml(htmlFile wave o)
    printf("ADC Diag: wrote %s\n" htmlFile)
    adcDiagOpenPage(htmlFile)
    htmlFile
  )
)

;; ---------- form ----------
procedure(adcDiagFormCB(form)
  adcDiagLast->psf  = form->psf->value
  adcDiagLast->net  = form->net->value
  adcDiagLast->fs   = form->fs->value
  adcDiagLast->t0   = form->t0->value
  adcDiagLast->n    = form->npts->value
  adcDiagLast->bits = form->bits->value
  adcDiagLast->m    = form->chans->value
  unless(errset(adcDiagRun(adcDiagLast) t)
    printf("ADC Diag: stopped. See the message above.\n"))
)

procedure(adcDiagShowForm()
  let((psf)
    psf = if(adcDiagLast->psf != "" then adcDiagLast->psf else adcDiagGuessPsf())
    unless(boundp('adcDiagForm) && adcDiagForm
      adcDiagForm = hiCreateAppForm(
        ?name      'adcDiagForm
        ?formTitle "ADC Output Diagnosis"
        ?callback  "adcDiagFormCB(hiGetCurrentForm())"
        ?fields    list(
          hiCreateStringField(?name 'psf   ?prompt "Results directory (psf)"  ?value psf)
          hiCreateStringField(?name 'net   ?prompt "ADC output signal"        ?value adcDiagLast->net)
          hiCreateFloatField( ?name 'fs    ?prompt "Sample rate Fs (Hz)"      ?value adcDiagLast->fs)
          hiCreateFloatField( ?name 't0    ?prompt "First sampling time (s)"  ?value adcDiagLast->t0)
          hiCreateIntField(   ?name 'npts  ?prompt "Number of samples N"      ?value adcDiagLast->n)
          hiCreateIntField(   ?name 'bits  ?prompt "Bits (0 = voltage data)"  ?value adcDiagLast->bits)
          hiCreateIntField(   ?name 'chans ?prompt "Interleaved channels M"   ?value adcDiagLast->m)
        )
      )
    )
    adcDiagForm->psf->value = psf
    hiDisplayForm(adcDiagForm)
  )
)

;; ---------- menu ----------
procedure(adcDiagInstallMenu()
  let((menu)
    unless(boundp('adcDiagMenuInstalled) && adcDiagMenuInstalled
      menu = hiCreatePulldownMenu('adcDiagMenu "ADC Diag"
        list(
          hiCreateMenuItem(?name 'adcDiagItemRun  ?itemText "Analyze ADC output..."   ?callback "adcDiagShowForm()")
          hiCreateMenuItem(?name 'adcDiagItemOpen ?itemText "Open ADC Diagnosis page" ?callback "adcDiagOpenTool()")
        )
      )
      hiInsertBannerMenu(window(1) menu hiGetNumMenus(window(1)))
      adcDiagMenuInstalled = t
    )
  )
)

adcDiagInstallMenu()
printf("ADC Diag: menu added to the CIW. Tool page: %s\n" adcDiagToolHtml)
