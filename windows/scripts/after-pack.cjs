// electron-builder afterPack: stamp the Syph icon and version info into the
// Windows executable with resedit (pure JS), so no Wine is needed to build on
// Linux or macOS.
const fs = require('node:fs')
const path = require('node:path')

exports.default = async function afterPack(context) {
  if (context.electronPlatformName !== 'win32') return
  const { NtExecutable, NtExecutableResource, Resource, Data } = require('resedit')
  const exePath = path.join(context.appOutDir, `${context.packager.appInfo.productFilename}.exe`)
  const exe = NtExecutable.from(fs.readFileSync(exePath), { ignoreCert: true })
  const res = NtExecutableResource.from(exe)

  const iconFile = Data.IconFile.from(fs.readFileSync(path.join(__dirname, '..', 'build', 'icon.ico')))
  Resource.IconGroupEntry.replaceIconsForResource(
    res.entries, 1, 1033, iconFile.icons.map((item) => item.data),
  )

  const version = context.packager.appInfo.version
  const [major, minor, patch] = version.split('.').map(Number)
  const infos = Resource.VersionInfo.fromEntries(res.entries)
  const info = infos[0] ?? Resource.VersionInfo.createEmpty()
  info.setFileVersion(major, minor, patch, 0, 1033)
  info.setProductVersion(major, minor, patch, 0, 1033)
  info.setStringValues({ lang: 1033, codepage: 1200 }, {
    CompanyName: 'Syph Software',
    FileDescription: 'Syph',
    ProductName: 'Syph',
    InternalName: 'Syph',
    OriginalFilename: 'Syph.exe',
    LegalCopyright: '© 2026 Syph Software',
    FileVersion: version,
    ProductVersion: version,
  })
  info.outputToResourceEntries(res.entries)
  res.outputResource(exe)
  fs.writeFileSync(exePath, Buffer.from(exe.generate()))
  console.log(`  • stamped icon and version into ${path.basename(exePath)}`)
}
