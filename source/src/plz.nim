include "constants/constants.nim"

type
  PyPI = object ## Base object.
    timeout: byte  ## Timeout Seconds for API Calls, byte type, 0~255.
    proxy: Proxy  ## Network IPv4 / IPv6 Proxy support, Proxy type.

using projectName, projectVersion, packageName, user, releaseVersion, destDir: string

template clientify(this: PyPI): untyped =
  ## Build & inject basic HTTP Client with Proxy and Timeout.
  var client {.inject.} = newHttpClient(
    timeout = when declared(this.timeout): this.timeout.int * 1_000 else: -1,
    proxy = when declared(this.proxy): this.proxy else: nil, userAgent="")

proc newPackages(this: PyPI): XmlNode =
  ## Return an RSS XML XmlNode type with the Newest Packages uploaded to PyPI.
  clientify(this)
  client.headers = headerXml
  result = parseXml(client.getContent(pypiPackagesXml))

proc lastUpdates(this: PyPI): XmlNode =
  ## Return an RSS XML XmlNode type with the Latest Updates uploaded to PyPI.
  clientify(this)
  client.headers = headerXml
  result = parseXml(client.getContent(pypiUpdatesXml))

proc lastJobs(this: PyPI): XmlNode =
  ## Return an RSS XML XmlNode type with the Latest Jobs posted to PyPI.
  clientify(this)
  client.headers = headerXml
  result = parseXml(client.getContent(pypiJobUrl))

proc project(this: PyPI, projectName): JsonNode =
  ## Return all JSON JsonNode type data for projectName from PyPI.
  preconditions projectName.len > 0
  clientify(this)
  client.headers = headerJson
  result = parseJson(client.getContent(pypiApiUrl & "pypi/" & projectName & "/json"))

proc release(this: PyPI, projectName, projectVersion): JsonNode =
  ## Return all JSON data for projectName of an specific version from PyPI.
  preconditions projectName.len > 0, projectVersion.len > 0
  clientify(this)
  client.headers = headerJson
  result = parseJson(client.getContent(pypiApiUrl & "pypi/" & projectName & "/" & projectVersion & "/json"))

proc htmlAllPackages(this: PyPI): string =
  ## Return all projects registered on PyPI as HTML string,Legacy Endpoint,Slow.
  clientify(this)
  result = client.getContent(url=pypiApiUrl & "simple")

proc htmlPackage(this: PyPI, projectName): string =
  ## Return a project registered on PyPI as HTML string, Legacy Endpoint, Slow.
  preconditions projectName.len > 0
  clientify(this)
  result = client.getContent(url=pypiApiUrl & "simple/" & projectName)

proc stats(this: PyPI): XmlNode =
  ## Return all JSON stats data for projectName of an specific version from PyPI.
  clientify(this)
  client.headers = headerXml
  result = parseXml(client.getContent(url=pypiStatus))

proc listPackages(this: PyPI): seq[string] =
  ## Return 1 XML XmlNode of **ALL** the Packages on PyPI. Server-side Slow.
  clientify(this)
  client.headers = headerXml
  for tagy in parseXml(client.postContent(pypiXmlUrl, body=lppXml)).findAll("string"): result.add tagy.innerText

proc changelogLastSerial(this: PyPI): int =
  ## Return 1 XML XmlNode with the Last Serial number integer.
  clientify(this)
  client.headers = headerXml
  for tagy in parseXml(client.postContent(pypiXmlUrl, body=clsXml)).findAll("int"): result = tagy.innerText.parseInt

proc listPackagesWithSerial(this: PyPI): seq[array[2, string]] =
  ## Return 1 XML XmlNode of **ALL** the Packages on PyPI with Serial number integer. Server-side Slow.
  clientify(this)
  client.headers = headerXml
  for tagy in parseXml(client.postContent(pypiXmlUrl, body=lpsXml)).findAll("member"):
    result.add [tagy.child"name".innerText, tagy.child"value".child"int".innerText]

proc packageLatestRelease(this: PyPI, packageName): string =
  ## Return the latest release registered for the given packageName.
  preconditions packageName.len > 0
  clientify(this)
  client.headers = headerXml
  let bodi = xmlRpcBody.format("package_releases", xmlRpcParam.format(packageName))
  for tagy in parseXml(client.postContent(pypiXmlUrl, body=bodi)).findAll("string"): result = tagy.innerText

proc packageRoles(this: PyPI, packageName): seq[XmlNode] =
  ## Retrieve a list of role, user for a given packageName. Role is Maintainer or Owner.
  preconditions packageName.len > 0
  clientify(this)
  client.headers = headerXml
  let bodi = xmlRpcBody.format("package_roles", xmlRpcParam.format(packageName))
  for tagy in parseXml(client.postContent(pypiXmlUrl, body=bodi)).findAll("data"): result.add tagy

proc userPackages(this: PyPI, user = user): seq[XmlNode] =
  ## Retrieve a list of role, packageName for a given user. Role is Maintainer or Owner.
  preconditions user.len > 0
  clientify(this)
  client.headers = headerXml
  let bodi = xmlRpcBody.format("user_packages", xmlRpcParam.format(user))
  for tagy in parseXml(client.postContent(pypiXmlUrl, body=bodi)).findAll("data"): result.add tagy

proc releaseUrls(this: PyPI, packageName, releaseVersion): seq[string] =
  ## Retrieve a list of download URLs for the given releaseVersion. Returns a list of dicts.
  preconditions packageName.len > 0, releaseVersion.len > 0
  clientify(this)
  client.headers = headerXml
  let bodi = xmlRpcBody.format("release_urls",
    xmlRpcParam.format(packageName) & xmlRpcParam.format(releaseVersion))
  for tagy in parseXml(client.postContent(pypiXmlUrl, body=bodi)).findAll("string"):
    if tagy.innerText.normalize.startsWith("https://"): result.add tagy.innerText

proc downloadPackage(this: PyPI, packageName, releaseVersion,
  destDir = getTempDir(), generateScript: bool): string =
  ## Download a URL for the given releaseVersion. Returns filename.
  preconditions packageName.len > 0, releaseVersion.len > 0, existsDir(destDir)
  let choosenUrl = this.releaseUrls(packageName, releaseVersion)[0]
  assert choosenUrl.startsWith("https://"), "PyPI Download URL is not HTTPS SSL"
  let filename = destDir / choosenUrl.split("/")[^1]
  clientify(this)
  info "⬇️\t" & choosenUrl
  if generateScript: script &= "curl -LO " & choosenUrl & "\n"
  client.downloadFile(choosenUrl, filename)
  assert existsFile(filename), "file failed to download"
  info "🗜\t" & $getFileSize(filename) & " Bytes total (compressed)"
  if findExe"sha256sum".len > 0: info "🔐\t" & execCmdEx(cmdChecksum & filename).output.strip
  try:
    info "⬇️\t" & choosenUrl & ".asc"
    client.downloadFile(choosenUrl & ".asc", filename & ".asc")
    if generateScript: script &= "curl -LO " & choosenUrl & ".asc" & "\n"
    if findExe"gpg".len > 0 and existsFile(filename & ".asc"):
      info "🔐\t" & execCmdEx(cmdVerify & filename & ".asc").output.strip
      if generateScript: script &= cmdVerify & filename.replace(destDir, "") & ".asc\n"
  except:
    warn "💩\tHTTP-404? ➡️ " & choosenUrl & ".asc (Package without PGP Signature)"
  if generateScript: script &= pipInstallCmd & filename.replace(destDir, "") & "\n"
  result = filename

proc installPackage(this: PyPI, packageName, releaseVersion: string,
  generateScript: bool): tuple[output: TaintedString, exitCode: int] =
  preconditions packageName.len > 0, releaseVersion.len > 0
  let packageFile = this.downloadPackage(
    packageName, releaseVersion, generateScript=generateScript)
  if unlikely(packageFile.endsWith".whl"): extract(packageFile, sitePackages)
  else:
    extract(packageFile, getTempDir())
    let path = packageFile[0..^5]
    if existsFile(path  / "setup.py"):
      let oldDir = getCurrentDir()
      setCurrentDir(path)
      result = execCmdEx(py3 & " " & path / "setup.py install --user")
      setCurrentDir(oldDir)

proc install(this: PyPI, args: seq[string]) =
  ## Install a Python package, download & decompress files, runs python setup.py
  var failed, suces: byte
  info("🐍\t" & $now() & ", PID is " & $getCurrentProcessId() & ", " &
    $args.len & " packages to download and install ➡️ " & $args)
  let generateScript = readLineFromStdin("Generate Install Script? (y/N): ").normalize == "y"
  let time0 = now()
  for argument in args:
    let semver = $this.packageLatestRelease(argument)
    info "🌎\tPyPI ➡️ " & argument & " " & semver
    let resultados = this.installPackage(argument, semver, generateScript)
    info (if resultados.exitCode == 0: "✅\t" else: "❌\t") & resultados.output
    if resultados.exitCode == 0: inc suces else: inc failed
  if generateScript: info "\n" & script
  info((if failed == 0: "✅\t" else: "❌\t") & $now() & " " & $failed &
    " Failed, " & $suces & " Success on " & $(now() - time0) &
    " to download/install " & $args.len & " packages")

proc download(this: PyPI, args: seq[string]) =
  ## Download a package to a local folder, dont decompress nor install.
  var where: string
  while not existsDir(where):
    where = readLineFromStdin("Download to where? (Full path to folder): ")
  for pkg in args:
    echo this.downloadPackage(pkg, $this.packageLatestRelease(pkg), where, false)

proc releaseData(this: PyPI, packageName, releaseVersion): XmlNode =
  ## Retrieve metadata describing a specific releaseVersion. Returns a dict.
  preconditions packageName.len > 0, releaseVersion.len > 0
  clientify(this)
  client.headers = headerXml
  let bodi = xmlRpcBody.format("release_data",
    xmlRpcParam.format(packageName) & xmlRpcParam.format(releaseVersion))
  result = parseXml(client.postContent(pypiXmlUrl, body=bodi))

proc search(this: PyPI, query: Table[string, seq[string]], operator="and"): XmlNode =
  ## Search package database using indicated search spec. Returns 100 results max.
  preconditions operator in ["or", "and"]
  clientify(this)
  client.headers = headerXml
  let bodi = xmlRpcBody.format("search", xmlRpcParam.format(replace($query, "@", "")) & xmlRpcParam.format(operator))
  result = parseXml(client.postContent(pypiXmlUrl, body=bodi))

proc browse(this: PyPI, classifiers: seq[string]): XmlNode =
  ## Retrieve a list of name, version of all releases classified with all of given classifiers.
  ## Classifiers must be a list of standard Trove classifier strings. Returns 100 results max.
  preconditions classifiers.len > 1
  clientify(this)
  client.headers = headerXml
  let clasifiers = block:
    var x: string
    for item in classifiers: x &= xmlRpcParam.format(item)
    x
  result = parseXml(client.postContent(pypiXmlUrl, body=xmlRpcBody.format("browse", clasifiers)))

proc upload(this: PyPI,
  name, version, license, summary, description, author, downloadurl, authoremail, maintainer, maintaineremail: string,
  homepage, filename, md5_digest, username, password: string, keywords: seq[string],
  requirespython=">=3", filetype="sdist", pyversion="source", description_content_type="text/markdown; charset=UTF-8; variant=GFM"): string =
  ## Upload 1 new version of 1 registered package to PyPI from a local filename.
  ## PyPI Upload is HTTP POST with MultipartData with HTTP Basic Auth Base64.
  ## For some unknown reason intentionally undocumented (security by obscurity?)
  # https://warehouse.readthedocs.io/api-reference/legacy/#upload-api
  # github.com/python/cpython/blob/master/Lib/distutils/command/upload.py#L131-L135
  preconditions(existsFile(filename), name.len > 0, version.len > 0, license.len > 0, summary.len > 0, description.len > 0, author.len > 0, downloadurl.len > 0,
  authoremail.len > 0, maintainer.len > 0, maintaineremail.len > 0, homepage.len > 0, md5_digest.len > 0, username.len > 0, password.len > 0, keywords.len > 0)
  let mime = newMimetypes().getMimetype(filename.splitFile.ext.toLowerAscii)
  # doAssert fext in ["whl", "egg", "zip"], "file extension must be 1 of .whl or .egg or .zip"
  let multipartData = block:
    var x = newMultipartData()
    x["protocol_version"] = "1"
    x[":action"] = "file_upload"
    x["metadata_version"] = "2.1"
    x["author"] = author
    x["name"] = name.normalize
    x["md5_digest"] = md5_digest # md5 hash of file in urlsafe base64
    x["summary"] = summary.normalize
    x["version"] = version.toLowerAscii
    x["license"] = license.toLowerAscii
    x["pyversion"] = pyversion.normalize
    x["requires_python"] = requirespython
    x["homepage"] = homepage.toLowerAscii
    x["filetype"] = filetype.toLowerAscii
    x["description"] = description.normalize
    x["keywords"] = keywords.join(" ").normalize
    x["download_url"] = downloadurl.toLowerAscii
    x["author_email"] = authoremail.toLowerAscii
    x["maintainer_email"] = maintaineremail.toLowerAscii
    x["description_content_type"] = description_content_type.strip
    x["maintainer"] = if maintainer == "": author else: maintainer
    x["content"] = (filename, mime, filename.readFile)
    x
  clientify(this) # TODO: Finish this and test against the test dev pypi server.
  client.headers = newHttpHeaders({"Authorization": "Basic " & encode(username & ":" & password), "dnt": "1"})
  result = client.postContent(pypiUploadUrl, multipart=multipartData)

proc pySkeleton() =
  ## Creates the skeleton (folders and files) for a New Python project.
  let pluginName = normalize(readLineFromStdin("New Python project name?: "))
  assert pluginName.len > 1, "Name must not be empty string: " & pluginName
  discard existsOrCreateDir(pluginName)
  discard existsOrCreateDir(pluginName / pluginName)
  writeFile(pluginName / pluginName / "__init__.py", r"print((lambda r:'\n'.join('.'.join('█' if(y<r and((x-r)**2+(y-r)**2<=r**2or(x-3*r)**2+(y-r)**2<=r**2))or(y>=r and x+r>=y and x-r<=4*r-y)else '░' for x in range(4*r))for y in range(1,3*r,2)))(5))")
  writeFile(pluginName / pluginName / "__main__.py", "\nprint('Main Module')\n")
  writeFile(pluginName / pluginName / "__version__.py", "__version__ = '0.0.1'\n")
  writeFile(pluginName / pluginName / "main.nim", nimpyTemplate)
  if readLineFromStdin("Generate optional Unitests on ./tests (y/N): ").normalize == "y":
    discard existsOrCreateDir(pluginName / "tests")
    writeFile(pluginName / "tests" / "__init__.py", testTemplate)
  if readLineFromStdin("Generate optional Documentation on ./docs (y/N): ").normalize == "y":
    discard existsOrCreateDir(pluginName / "docs")
    writeFile(pluginName / "docs" / "documentation.md", "# " & pluginName & "\n\n")
  if readLineFromStdin("Generate optional Examples on ./examples (y/N): ").normalize == "y":
    discard existsOrCreateDir(pluginName / "examples")
    writeFile(pluginName / "examples" / "example.py", "# -*- coding: utf-8 -*-\n\nprint('Example')\n")
  if readLineFromStdin("Generate optional DevOps on ./devops (y/N): ").normalize == "y":
    discard existsOrCreateDir(pluginName / "devops")
    writeFile(pluginName / "devops" / "Dockerfile", dockerfileTemplate)
    writeFile(pluginName / "devops" / pluginName & ".service", serviceTemplate)
    writeFile(pluginName / "devops" / "build_package.sh", "python3 setup.py sdist --formats=zip\n")
    writeFile(pluginName / "devops" / "upload_package.sh", "twine upload .\n")
  if readLineFromStdin("Generate optional GitHub files on .github (y/N): ").normalize == "y":
    discard existsOrCreateDir(pluginName / ".github")
    discard existsOrCreateDir(pluginName / ".github/ISSUE_TEMPLATE")
    discard existsOrCreateDir(pluginName / ".github/PULL_REQUEST_TEMPLATE")
    writeFile(pluginName / ".github/ISSUE_TEMPLATE/ISSUE_TEMPLATE.md", "")
    writeFile(pluginName / ".github/PULL_REQUEST_TEMPLATE/PULL_REQUEST_TEMPLATE.md", "")
    writeFile(pluginName / ".github/FUNDING.yml", "")
  if readLineFromStdin("Generate .gitignore file (y/N): ").normalize == "y":
    writeFile(pluginName / ".gitattributes", "*.py linguist-language=Python\n*.nim linguist-language=Nim\n")
    writeFile(pluginName / ".gitignore", "*.pyc\n*.pyd\n*.pyo\n*.egg-info\n*.egg\n*.log\n__pycache__\n*.c\n*.h\n*.o\n")
    writeFile(pluginName / ".coveragerc", "")
  if readLineFromStdin("Generate Pre-Commit files (y/N): ").normalize == "y":
    discard existsOrCreateDir(pluginName / ".hooks")
    writeFile(pluginName / ".hooks" / "pre-commit", precommitTemplate)
  if readLineFromStdin("Generate optional files (y/N): ").normalize == "y":
    writeFile(pluginName / "MANIFEST.in", "include main.py\nrecursive-include *.py\n")
    writeFile(pluginName / "requirements.txt", "")
    writeFile(pluginName / "setup.cfg", setupCfg)
    writeFile(pluginName / "Makefile", "")
    writeFile(pluginName / "setup.py", "# -*- coding: utf-8 -*-\nfrom setuptools import setup\nsetup() # Edit setup.cfg,not here!.\n")
    let ext = if readLineFromStdin("Use Markdown(MD) instead of ReSTructuredText(RST)  (y/N): ").normalize == "y": "md" else: "rst"
    writeFile(pluginName / "LICENSE." & ext, "See https://tldrlegal.com/licenses/browse\n")
    writeFile(pluginName / "CODE_OF_CONDUCT." & ext, "")
    writeFile(pluginName / "CONTRIBUTING." & ext, "")
    writeFile(pluginName / "AUTHORS." & ext, "# Authors\n\n- " & user & "\n")
    writeFile(pluginName / "README." & ext, "# " & pluginName & "\n")
    writeFile(pluginName / "CHANGELOG." & ext, "# 0.0.1\n\n- First initial version of " & pluginName & "created at " & $now())
  quit("Created a new Python project skeleton, happy hacking, bye...\n", 0)

template enUsUtf8() =
  for envar in ["LC_CTYPE", "LC_NUMERIC", "LC_TIME", "LC_COLLATE", "LC_NAME",
  "LC_MONETARY", "LC_MESSAGES", "LC_PAPER", "LC_ADDRESS", "LC_TELEPHONE", "LANG",
  "LC_MEASUREMENT", "LC_IDENTIFICATION", "LC_ALL"]: putEnv(envar, "en_US.UTF-8")

proc backup(): tuple[output: TaintedString, exitCode: int] =
  var folder: string
  while not(folder.len > 0 and existsDir(folder)):
    folder = readLineFromStdin("Full path of 1 existing folder to Backup?: ").strip
  var files2backup: seq[string]
  for pythonfile in walkFiles(folder / "*.*"):
    files2backup.add pythonfile
    styledEcho(fgGreen, bgBlack, "🗜\t" & pythonfile)
  if files2backup.len > 0 and findExe"tar".len > 0:
    result = execCmdEx(cmdTar & folder & ".tar.gz " & files2backup.join" ")
    if result.exitCode == 0 and findExe"sha256sum".len > 0 and readLineFromStdin("SHA256 CheckSum Backup? (y/N): ").normalize == "y":
      result = execCmdEx(cmdChecksum & folder & ".tar.gz > " & folder & ".tar.gz.sha256")
    if result.exitCode == 0 and findExe"gpg".len > 0 and readLineFromStdin("GPG Sign Backup? (y/N): ").normalize == "y":
      result = execCmdEx(cmdSign & folder & ".tar.gz")

proc ask2User(): auto =
  var username, password, name, version, license, summary, description, homepage: string
  var author, downloadurl, authoremail, maintainer, maintaineremail, iPwd2: string
  var keywords: seq[string]
  while not(author.len > 2 and author.len < 99):
    author = readLineFromStdin("\nType Author (Real Name): ").strip
  while not(username.len > 2 and username.len < 99):
    username = readLineFromStdin("Type Username (PyPI Username): ").strip
  while not(maintainer.len > 2 and maintainer.len < 99):
    maintainer = readLineFromStdin("Type Package Maintainer (Real Name): ").strip
  while not(password.len > 4 and password.len < 999 and password == iPwd2):
    password = readLineFromStdin("Type Password: ").strip  # Type it Twice.
    iPwd2 = readLineFromStdin("Confirm Password (Repeat it again): ").strip
  while not(authoremail.len > 5 and authoremail.len < 255 and "@" in authoremail):
    authoremail = readLineFromStdin("Type Author Email (Lowercase): ").strip.toLowerAscii
  while not(maintaineremail.len > 5 and maintaineremail.len < 255 and "@" in maintaineremail):
    maintaineremail = readLineFromStdin("Type Maintainer Email (Lowercase): ").strip.toLowerAscii
  while not(name.len > 0 and name.len < 99):
    name = readLineFromStdin("Type Package Name: ").strip.toLowerAscii
  while not(version.len > 4 and version.len < 99 and "." in version):
    version = readLineFromStdin("Type Package Version (SemVer): ").normalize
  info licenseHint
  while not(license.len > 2 and license.len < 99):
    license = readLineFromStdin("Type Package License: ").normalize
  while not(summary.len > 0 and summary.len < 999):
    summary = readLineFromStdin("Type Package Summary (Short Description): ").strip
  while not(description.len > 0 and description.len < 999):
    description = readLineFromStdin("Type Package Description (Long Description): ").strip
  while not(homepage.len > 5 and homepage.len < 999 and homepage.startsWith"http"):
    homepage = readLineFromStdin("Type Package Web Homepage URL (HTTP/HTTPS): ").strip.toLowerAscii
  while not(downloadurl.len > 5 and downloadurl.len < 999 and downloadurl.startsWith"http"):
    downloadurl = readLineFromStdin("Type Package Web Download URL (HTTP/HTTPS): ").strip.toLowerAscii
  while not(keywords.len > 1 and keywords.len < 99):
    keywords = readLineFromStdin("Type Package Keywords,separated by commas,without spaces,at least 2 (CSV): ").normalize.split(",")
  result = (username: username, password: password, name: name, author: author,
    version: version, license: license, summary: summary, homepage: homepage,
    description: description,  downloadurl: downloadurl, maintainer: maintainer,
    authoremail: authoremail,  maintaineremail: maintaineremail, keywords: keywords)

proc forceInstallPip(destination: string): tuple[output: TaintedString, exitCode: int] =
  preconditions destination.endsWith".py"
  newHttpClient(timeout=9999).downloadFile(pipInstaller, destination) # Download
  assert existsFile(destination), "File not found: 'get-pip.py' " & destination
  result = execCmdEx(py3 & destination & " -I") # Installs PIP via get-pip.py

proc parseRecord(filename: string): seq[seq[string]] =
  ## Parse RECORD files from Python packages, they are Headerless CSV.
  preconditions filename.endsWith"RECORD", existsFile(filename)
  postconditions result.len > 0
  var parser: CsvParser
  var stream = newFileStream(filename, fmRead)
  assert stream != nil, "Failed to parse a CSV from file to string stream"
  open(parser, stream, filename)
  while readRow(parser): result.add parser.row
  close(parser)

proc uninstall(this: PyPI, args: seq[string]) =
  ## Uninstall a Python package, deletes the files, optional uninstall script.
  # /usr/lib/python3.7/site-packages/PACKAGENAME-1.0.0.dist-info/RECORD is a CSV
  preconditions args.len > 0
  styledEcho(fgGreen, bgBlack, "Uninstall " & $args.len & " Packages:\t" & $args)
  let recordFiles = block:
    var output: seq[string]
    for argument in args:
      for record in walkFiles(sitePackages / argument & "-*.dist-info" / "RECORD"):
        output.add record  # RECORD Metadata file (CSV without file extension).
    output
  assert recordFiles.len > 0, "RECORD Metadata CSV files not found."
  # echo "Found " & $recordFiles.len & " Metadata files: " & $recordFiles
  let files2delete = block:
    var output: seq[string]
    var size: int
    for record in recordFiles:
      for recordfile in parseRecord(record):
        output.add sitePackages / recordfile[0]
        if recordfile.len == 3 and recordfile[2].len > 0:
          size += parseInt(recordfile[2])
    styledEcho(fgGreen, bgBlack, "Total disk space freed:\t" &
      formatSize(size.int64, prefix = bpColloquial, includeSpace = true))
    output
  assert files2delete.len > 0, "Files of a Python Package not found."
  if readLineFromStdin("\nGenerate Uninstall Script? (y/N): ").normalize == "y":
    let sudo =
      if readLineFromStdin("\nGenerate Uninstall Script for Admin/Root? (y/N): ").normalize == "y":
        when defined(windows): "\nrunas /user:Administrator " else: "\nsudo "
      else: "\n"
    const cmd = when defined(windows): "del " else: "rm --verbose --force "
    info(sudo & cmd & files2delete.join" " & "\n")
  for pyfile in files2delete:
    styledEcho(fgRed, bgBlack, "🗑\t" & pyfile)
  if readLineFromStdin("\nDelete " & $files2delete.len & " files? (y/N): ").normalize == "y":
    styledEcho(fgRed, bgBlack, "\n\nDeleted?\tFile")
    for pythonfile in files2delete:
      info $tryRemoveFile(pythonfile) & "\t" & pythonfile


###############################################################################


when isMainModule:  # https://pip.readthedocs.io/en/1.1/requirements.html
  var taimaout = 99.byte
  var args: seq[string]
  for tipoDeClave, clave, valor in getopt():
    case tipoDeClave
    of cmdShortOption, cmdLongOption:
      case clave.normalize
      of "version": quit(version, 0)
      of "license", "licencia": quit("PPL", 0)
      of "nice20": discard nice(20.cint)
      of "timeout": taimaout = valor.parseInt.byte
      of "help", "ayuda", "fullhelp":
        styledEcho(fgGreen, bgBlack, helpy)
        quit()
      of "publicip":
        quit(newHttpClient(timeout=9999).getContent("https://api.ipify.org").strip, 0)
      of "debug", "desbichar":
        quit(pretty(%*{"CompileDate": CompileDate, "CompileTime": CompileTime,
        "NimVersion": NimVersion, "hostCPU": hostCPU, "hostOS": hostOS,
        "cpuEndian": cpuEndian, "tempDir": getTempDir(),
        "currentDir": getCurrentDir(), "python3": py3, "ssl": defined(ssl),
        "release": defined(release), "contracts": defined(release),
        "hardened": defined(hardened), "sitePackages": sitePackages,
        "pipCacheDir": pipCacheDir,
        "currentCompilerExe": getCurrentCompilerExe(), "int.high": int.high,
        "processorsCount": countProcessors(), "danger": defined(danger),
        "currentProcessId": getCurrentProcessId(), "version": version}), 0)
      of "enusutf8": enUsUtf8()
      of "putenv":
        let envy = valor.split"="
        styledEcho(fgMagenta, bgBlack, $envy)
        putEnv(envy[0], envy[1])
      of "nopyc":
        styledEcho(fgRed, bgBlack, "\n\nDeleted?\tFile")
        for pyc in walkFiles(getCurrentDir() / "*.pyc"): info $tryRemoveFile(pyc) & "\t" & pyc
        for pyc in walkDirs(getCurrentDir() / "__pycache__"): info $tryRemoveFile(pyc) & "\t" & pyc
      of "cleantemp":
        styledEcho(fgRed, bgBlack, "\n\nDeleted?\tFile")
        for tmp in walkPattern(getTempDir() / "**" / "*.*"): info $tryRemoveFile(tmp) & "\t" & tmp
        for tmp in walkPattern(getTempDir() / "**" / "*"): info $tryRemoveFile(tmp) & "\t" & tmp
      of "nopypackages":
        styledEcho(fgRed, bgBlack, "\n\nDeleted?\tFile")
        for pyc in walkFiles(getCurrentDir() / "__pypackages__"): info $tryRemoveFile(pyc) & "\t" & pyc
      of "cleanvirtualenvs", "cleanvirtualenv", "clearvirtualenvs", "clearvirtualenv":
        let files2delete = block:
          var x: seq[string]
          for pythonfile in walkPattern(virtualenvDir / "*.*"):
            styledEcho(fgRed, bgBlack, "🗑\t" & pythonfile)
            #if readLineFromStdin("Delete Python Virtualenv? (y/N): ").normalize == "y":
            x.add pythonfile
          x # No official documented way to get virtualenv location on windows
        info("files2delete " & files2delete)
        styledEcho(fgRed, bgBlack, "\n\nDeleted?\tFile")
        for pyc in files2delete: info $tryRemoveFile(pyc) & "\t" & pyc
        quit()
      of "cleanpipcache":
        styledEcho(fgRed, bgBlack, "\n\nDeleted?\tFile") # Dir Found in the wild
        info $tryRemoveFile("/tmp/pip-build-root") & "\t/tmp/pip-build-root"
        info $tryRemoveFile("/tmp/pip_build_root") & "\t/tmp/pip_build_root"
        info $tryRemoveFile("/tmp/pip-build-" & user) & "\t/tmp/pip-build-" & user
        info $tryRemoveFile("/tmp/pip_build_" & user) & "\t/tmp/pip_build_" & user
        info $tryRemoveFile(pipCacheDir) & "\t" & pipCacheDir
      of "color":
        setBackgroundColor(bgBlack)
        setForegroundColor(fgGreen)
      of "suicide": discard tryRemoveFile(currentSourcePath()[0..^5])
    of cmdArgument:
      args.add clave
    of cmdEnd: quit("Wrong Parameters, please see Help with: --help", 1)

  let is1argOnly = args.len == 2  # command + arg == 2 ("install foo")
  if args.len > 0:
    let cliente = PyPI(timeout: taimaout)
    case args[0].normalize
    of "stats":
      quit($cliente.stats(), 0)
    of "newpackages":
      quit($cliente.newPackages(), 0)
    of "lastupdates":
      quit($cliente.lastUpdates(), 0)
    of "lastjobs":
      quit($cliente.lastJobs(), 0)
    of "latestversion":
      if not is1argOnly: quit"Too many arguments,command only supports 1 argument"
      quit($cliente.packageLatestRelease(args[1]), 0)
    of "open":
      if not is1argOnly: quit"Too many arguments,command only supports 1 argument"
      discard execCmdEx(osOpen & args[1])
    of "userpackages":
      quit($cliente.userPackages(readLineFromStdin("PyPI Username?: ").normalize), 0)
    of "strip":
      if not is1argOnly: quit"Too many arguments,command only supports 1 argument"
      let (output, exitCode) = execCmdEx(cmdStrip & args[1])
      quit(output, exitCode)
    of "search":
      quit("Not implemented yet (PyPI API is Buggy)")
      # info args[1]
      # info cliente.search({"name": @[args[1]]}.toTable)
    of "init":
      pySkeleton()
    of "hash":
      if not is1argOnly: quit"Too many arguments,command only supports 1 argument"
      if findExe"sha256sum".len > 0:
        let sha512sum = execCmdEx(cmdChecksum & args[1]).output.strip
        info sha512sum
        info "--hash=sha256:" & sha512sum.split(" ")[^1]
    of "backup": quit(backup().output, 0)
    of "uninstall":
      cliente.uninstall(args[1..^1])
    of "install":
      cliente.install(args[1..^1])
    of "reinstall":
      let packages = args[1..^1]
      cliente.uninstall(packages)
      cliente.install(packages)
    of "download":
      cliente.download(args[1..^1])
    of "upload":
      if not is1argOnly: quit"Too many arguments,command only supports 1 argument"
      doAssert existsFile(args[1]), "File not found: " & args[1]
      let (username, password, name, author, version, license, summary, homepage,
        description, downloadurl, maintainer, authoremail, maintaineremail, keywords
      ) = ask2User()
      info cliente.upload(
        username = username, password = password, name = name,
        version = version, license = license, summary = summary,
        description = description, author = author, downloadurl = downloadurl,
        authoremail = authoremail, maintainer = maintainer, keywords = keywords,
        maintaineremail = maintaineremail, homepage = homepage, filename = args[1],
        md5_digest = getMD5(readFile(args[1])),
      )

  else: quit("Wrong Parameters, please see Help with: --help", 1)
