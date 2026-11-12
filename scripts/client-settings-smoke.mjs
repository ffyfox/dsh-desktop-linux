/** TEST ONLY: prepended to a disposable bundle by smoke-client-settings.py. */
import * as smokeElectron from 'electron'
import * as smokeFs from 'node:fs/promises'
import { join as smokeJoin } from 'node:path'
const smokeDir = process.env.DSH_CLIENT_SMOKE_OUTPUT
const smokeDelay = ms => new Promise(resolve => setTimeout(resolve, ms))
const smokeStyles = ['macos', 'fusion', 'windows', 'macos']
const smokeRadii = [12, 24, 12, 0]
const smokeOpacity = [80, 75, 80, 60]
let smokeTray
let smokePopups = 0
const smokeSetMenu = smokeElectron.Tray.prototype.setContextMenu
smokeElectron.Tray.prototype.setContextMenu = function (menu) { smokeTray = menu; return smokeSetMenu.call(this, menu) }
const smokePopup = smokeElectron.Menu.prototype.popup
smokeElectron.Menu.prototype.popup = function (options) {
  smokePopups++
  setTimeout(() => this.closePopup(options.window), 200)
  return smokePopup.call(this, options)
}
const smokeDialog = smokeElectron.dialog.showMessageBox
smokeElectron.dialog.showMessageBox = function (...args) {
  const options = args.at(-1)
  if (String(options.title).includes('重启') || String(options.title).toLowerCase().includes('restart')) return Promise.resolve({ response: 1, checkboxChecked: false })
  return smokeDialog.apply(this, args)
}
let smokeStarted = false
smokeElectron.app.on('browser-window-created', (_event, window) => {
  window.webContents.on('did-finish-load', async () => {
    if (smokeStarted || !window.webContents.getURL().startsWith('dsh-app://app/')) return
    smokeStarted = true
    const assert = (ok, message) => { if (!ok) throw new Error(message); console.info('CLIENT_SMOKE PASS ' + message) }
    const until = async predicate => { for (let count = 0; count < 160; count++) { if (await predicate()) return; await smokeDelay(100) }; throw new Error('readiness timeout') }
    const page = script => window.webContents.executeJavaScript(script)
    const capture = async name => {
      await smokeDelay(200)
      await smokeFs.writeFile(smokeJoin(smokeDir, name), (await window.webContents.capturePage()).toPNG())
    }
    const clickPoint = async (x, y) => {
      const point={x:Math.round(x),y:Math.round(y),button:'left',clickCount:1}
      window.webContents.sendInputEvent({type:'mouseDown',...point}); window.webContents.sendInputEvent({type:'mouseUp',...point})
      await smokeDelay(100)
    }
    const clickSelector = async selector => {
      const box=await page(`(() => { const r=document.querySelector(${JSON.stringify(selector)}).getBoundingClientRect(); return {x:r.x+r.width/2,y:r.y+r.height/2}; })()`)
      await clickPoint(box.x, box.y)
    }
    try {
      await until(() => page("!!document.querySelector('dsh-kde-window-controls')"))
      const prefs = window.webContents.getLastWebPreferences()
      assert(prefs.sandbox && prefs.contextIsolation && !prefs.nodeIntegration, 'main renderer sandbox preserved')
      const stageFile = smokeJoin(smokeDir, 'stage.json')
      let stage = 0
      try { stage = JSON.parse(await smokeFs.readFile(stageFile, 'utf8')).stage } catch (error) { if (error.code !== 'ENOENT') throw error }
      await until(() => page("!!document.querySelector('[data-window-drag]')"))
      const expectedGlass = stage < 3
      await until(async () => (await page("document.documentElement.hasAttribute('data-dsh-glass')")) === expectedGlass)
      assert((await page("document.documentElement.hasAttribute('data-dsh-glass')")) === expectedGlass, `stage ${stage} startup sidebar material`)
      await until(() => smokeTray?.items.some(item => /客户端设置|Client settings/u.test(item.label)))
      const item = smokeTray.items.find(item => /客户端设置|Client settings/u.test(item.label))
      item.click()
      await until(() => smokeElectron.BrowserWindow.getAllWindows().some(win => win.webContents.getURL().endsWith('/client-settings.html')))
      const settings = smokeElectron.BrowserWindow.getAllWindows().find(win => win.webContents.getURL().endsWith('/client-settings.html'))
      await until(() => settings.webContents.executeJavaScript("!document.getElementById('appearance-form').hidden"))
      const settingsPrefs = settings.webContents.getLastWebPreferences()
      assert(settingsPrefs.sandbox && settingsPrefs.contextIsolation && !settingsPrefs.nodeIntegration, 'settings renderer sandbox preserved')
      const evaluate = script => settings.webContents.executeJavaScript(script)
      const snapshot = await evaluate('window.dshClientSettings.get()')
      assert(snapshot.kind === 'ok', 'real isolated settings IPC returns snapshot')
      const expectedStyle = smokeStyles[stage]
      const expectedRadius = smokeRadii[stage]
      assert(snapshot.value.current.titlebarStyle === expectedStyle, `stage ${stage} saved ${expectedStyle} style reloaded`)
      assert((await page("document.documentElement.getAttribute('data-dsh-titlebar-style')")) === expectedStyle, `stage ${stage} real title-bar style applied`)
      assert(snapshot.value.defaults.sidebarOpacity === 80, 'default transparency is twenty percent')
      assert(snapshot.value.current.sidebarOpacity === smokeOpacity[stage], 'saved transparency remains unchanged across style changes')
      assert(snapshot.value.current.cornerRadius === expectedRadius, `stage ${stage} saved radius reloaded`)
      const clipPath = await page('getComputedStyle(document.documentElement).clipPath')
      assert(clipPath.includes(`${expectedRadius}px`), `stage ${stage} real renderer corner clipping applied`)
      assert(snapshot.value.current.systemShadow === (stage !== 1), `stage ${stage} saved system shadow reloaded`)
      const count = smokeElectron.BrowserWindow.getAllWindows().length
      item.click(); await smokeDelay(50)
      assert(smokeElectron.BrowserWindow.getAllWindows().length === count, 'tray settings window is singleton')
      if (expectedGlass) {
        const fade = await page(`(() => { const node=document.querySelector('[data-sidebar-scrollport] + span[aria-hidden="true"]'); return node && { display:getComputedStyle(node).display, oldSelector:node.matches('[class$="_fade"]') }; })()`)
        assert(fade && fade.display === 'none' && !fade.oldSelector, `stage ${stage} sidebar fade stays removed`)
      }
      settings.setAlwaysOnTop(false)
      window.show(); window.focus(); await smokeDelay(200)
      if (expectedStyle !== 'macos') {
        const clickControl = async offset => {
          const box=await page(`(() => { const r=document.querySelector('dsh-kde-window-controls').getBoundingClientRect(); return {x:r.left,y:r.top,width:r.width,height:r.height}; })()`)
          assert(box.x > 0 && box.width === 138 && box.height === (expectedStyle === 'windows' ? 40 : 48), `${expectedStyle} controls use the correct right-edge row`)
          await clickPoint(box.x+offset,box.y+box.height/2)
        }
        await clickControl(69); await until(() => window.isMaximized())
        await clickControl(69); await until(() => !window.isMaximized())
        await clickControl(23); await until(() => window.isMinimized())
        window.restore(); window.focus(); await until(() => !window.isMinimized())
        assert(true, `trusted ${expectedStyle} minimize/maximize/restore controls operate native window`)
      }
      if (expectedStyle === 'fusion') {
        const rows = await page(`(() => { const toggle=document.querySelector('[data-sidebar-toggle]'); const logo=toggle.parentElement.nextElementSibling; const a=toggle.getBoundingClientRect(),b=logo.getBoundingClientRect(); return {toggleY:a.y+a.height/2,logoY:b.y+b.height/2,rowHeight:b.height,menu:!!document.querySelector('[data-windows-menu]')}; })()`)
        assert(Math.abs(rows.toggleY-rows.logoY) <= 2 && rows.rowHeight === 40 && !rows.menu, 'Blended toggle and logo share one row without a caption menu')
        await capture('titlebar-fusion.png')
        await clickSelector('[data-sidebar-toggle]'); await until(() => page("!!document.querySelector('[data-sidebar-collapsed]')"))
        await until(() => page("document.querySelector('[class*=sidebarCol]').getBoundingClientRect().width < 1"))
        await smokeDelay(700)
        await capture('titlebar-fusion-collapsed.png')
        await clickSelector('[data-sidebar-opener]'); await until(() => page("!document.querySelector('[data-sidebar-collapsed]')"))
      }
      if (expectedStyle === 'windows') {
        await until(() => page("!!document.querySelector('[data-windows-menu]')"))
        const geometry = await page(`(() => { const toggle=document.querySelector('[data-sidebar-toggle]').getBoundingClientRect();const frame=document.querySelector('div:has(> [class*="sidebarCol"])');const menu=document.querySelector('[data-windows-menu]');return {padding:getComputedStyle(frame).paddingTop,toggleY:toggle.y+toggle.height/2,menu:Array.from(menu.shadowRoot.querySelectorAll('button')).map(x=>x.textContent)};})()`)
        assert(geometry.padding === '40px' && geometry.toggleY === 20 && geometry.menu.length === 2, 'Windows reuses upstream forty-pixel caption, sidebar toggle and Application/Edit menu')
        const popupBefore=smokePopups
        const application=await page(`(() => { const r=document.querySelector('[data-windows-menu]').shadowRoot.querySelector('button').getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};})()`)
        await clickPoint(application.x,application.y); await until(() => smokePopups > popupBefore)
        await smokeDelay(250)
        assert(true, 'trusted Windows Application menu opens the native popup')
        await page(`document.activeElement?.blur()`)
        window.webContents.sendInputEvent({type:'mouseMove',x:600,y:200})
        await capture('titlebar-windows.png')
        await page("document.body.setAttribute('data-ds-dark-theme','')")
        await capture('titlebar-windows-dark.png')
        await page("document.body.removeAttribute('data-ds-dark-theme')")
        await clickSelector('[data-sidebar-toggle]'); await until(() => page("!!document.querySelector('[data-sidebar-collapsed]')"))
        await until(() => page("document.querySelector('[class*=sidebarCol]').getBoundingClientRect().width < 1"))
        await smokeDelay(700)
        await capture('titlebar-windows-collapsed.png')
        await clickSelector('[data-sidebar-toggle]'); await until(() => page("!document.querySelector('[data-sidebar-collapsed]')"))
        window.setFullScreen(true); await until(() => window.isFullScreen())
        await until(() => page("document.querySelector('dsh-kde-window-controls').hidden"))
        assert(await page("getComputedStyle(document.querySelector('[data-windows-menu]')).display === 'none'"), 'Windows fullscreen hides caption menus and buttons')
        window.setFullScreen(false); await until(() => !window.isFullScreen())
        await until(() => page("!document.querySelector('dsh-kde-window-controls').hidden"))
      }
      if (stage === 3) {
        await smokeFs.writeFile(smokeJoin(smokeDir, 'result.json'), JSON.stringify({ok:true,stages:4,nativeWayland:true,sandbox:true,tray:true,restart:true,sidebarOpacity:true,shadowToggle:true,cornerRadius:true,titlebarStyle:true,sidebarFade:true,trustedWindowsControls:true,nativeCaptionMenu:true,blendedLogoRow:true},null,2)+'\n')
        settings.close(); assert(!window.isDestroyed(), 'closing settings preserves primary window')
        console.info('CLIENT_SMOKE COMPLETE'); smokeElectron.app.quit(); return
      }
      settings.show(); settings.focus()
      if (stage === 0) {
        await smokeDelay(200)
        await smokeFs.writeFile(smokeJoin(smokeDir, 'settings-window.png'), (await settings.webContents.capturePage()).toPNG())
        window.show(); window.focus()
        const fadeBefore = await page(`(() => { const node=document.querySelector('[data-sidebar-scrollport] + span[aria-hidden="true"]');node.style.display='block';const r=node.getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height};})()`)
        await smokeFs.writeFile(smokeJoin(smokeDir, 'sidebar-fade-metrics.json'), JSON.stringify(fadeBefore,null,2)+'\n')
        await capture('sidebar-fade-before.png')
        await page(`document.querySelector('[data-sidebar-scrollport] + span[aria-hidden="true"]').style.removeProperty('display')`)
        await capture('titlebar-macos.png'); await capture('frameless-main.png'); settings.focus()
      }
      const next=stage+1
      await evaluate(`(() => {
        const radius=document.getElementById('corner-radius');radius.value='${smokeRadii[next]}';radius.dispatchEvent(new Event('input',{bubbles:true}));
        const trans=document.getElementById('sidebar-transparency');trans.value='${100-smokeOpacity[next]}';trans.dispatchEvent(new Event('input',{bubbles:true}));
        const style=document.getElementById('titlebar-style');style.value='${smokeStyles[next]}';style.dispatchEvent(new Event('change',{bubbles:true}));
        document.getElementById('system-shadow').checked=${next !== 1};
        document.getElementById('sidebar-glass').checked=${next < 3};
        document.getElementById('save').click();
      })()`)
      await until(async () => (await evaluate('window.dshClientSettings.get()')).value?.saved.cornerRadius === smokeRadii[next])
      const saved = await evaluate('window.dshClientSettings.get()')
      assert(saved.value.saved.sidebarOpacity === smokeOpacity[next], 'transparency input saved with inverse opacity semantics')
      assert(saved.value.saved.titlebarStyle === smokeStyles[next] && saved.value.current.titlebarStyle === expectedStyle, 'title-bar changes are saved for next restart, not applied live')
      assert(saved.value.current.cornerRadius === expectedRadius && saved.value.restartRequired, 'save preserves current-run appearance and requests restart')
      await smokeFs.writeFile(stageFile, JSON.stringify({stage:next}))
      const restarted = await evaluate('window.dshClientSettings.restart()').catch(() => undefined)
      if (restarted !== undefined) assert(restarted.kind === 'ok', 'confirmed restart accepted')
    } catch (error) {
      await smokeFs.writeFile(smokeJoin(smokeDir, 'result.json'), JSON.stringify({ok:false,error:String(error.stack||error)},null,2)+'\n')
      console.error('CLIENT_SMOKE FAIL '+error.stack); smokeElectron.app.exit(1)
    }
  })
})
setTimeout(() => { console.error('CLIENT_SMOKE FAIL timeout'); smokeElectron.app.exit(2) }, 65000).unref()
