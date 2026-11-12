/** TEST ONLY: native captures of the Windows content corner in a disposable profile. */
import * as cornerElectron from 'electron'
import * as cornerFs from 'node:fs/promises'
import { join as cornerJoin } from 'node:path'
const cornerOutput = process.env.DSH_CLIENT_SMOKE_OUTPUT
const cornerExpectHole = process.env.DSH_CLIENT_CORNER_EXPECT_HOLE === '1'
const cornerDelay = ms => new Promise(resolve => setTimeout(resolve, ms))
let cornerStarted = false
cornerElectron.app.on('browser-window-created', (_event, window) => {
  window.webContents.on('did-finish-load', async () => {
    if (cornerStarted || !window.webContents.getURL().startsWith('dsh-app://app/')) return
    cornerStarted = true
    const check = (ok, text) => { if (!ok) throw new Error(text); console.info('CLIENT_SMOKE PASS '+text) }
    const page = expression => window.webContents.executeJavaScript(expression)
    const until = async predicate => {
      for (let attempt=0; attempt<160; attempt++) { if (await predicate()) return; await cornerDelay(100) }
      throw new Error('corner smoke readiness timeout')
    }
    const records = []
    const capture = async (name, {collapsed=false, fullscreen=false, maximized=false} = {}) => {
      await cornerDelay(250)
      const geometry = await page(`(() => {
        const center=document.querySelector('div:has(> [class*="sidebarCol"]) > [class*="centerCol"]');
        const frame=center.parentElement, sidebar=frame.querySelector(':scope > [class*="sidebarCol"]');
        const rect=center.getBoundingClientRect(), style=getComputedStyle(frame);
        return {left:rect.left,top:rect.top,width:innerWidth,height:innerHeight,radius:getComputedStyle(center).borderTopLeftRadius,
          sidebarWidth:sidebar.getBoundingClientRect().width,backing:style.backgroundImage,backingSize:style.backgroundSize,
          backingPosition:style.backgroundPosition,clip:getComputedStyle(document.documentElement).clipPath,
          style:document.documentElement.dataset.dshTitlebarStyle};
      })()`)
      const image = await window.webContents.capturePage()
      await cornerFs.writeFile(cornerJoin(cornerOutput, name+'.png'), image.toPNG())
      const size=image.getSize(1), bitmap=image.toBitmap({scaleFactor:1})
      const pixel = (x,y) => {
        const px=Math.round(x*size.width/geometry.width), py=Math.round(y*size.height/geometry.height)
        const offset=(py*size.width+px)*4
        return [...bitmap.subarray(offset,offset+4)]
      }
      const notch=pixel(geometry.left+2,geometry.top+2)
      const caption=pixel(geometry.width/2,20)
      const content=pixel(Math.min(geometry.left+50,geometry.width-20),geometry.top+28)
      const outside=pixel(0,0)
      const sidebar=collapsed ? undefined : pixel(Math.max(20,geometry.left/2),geometry.height-120)
      records.push({name,geometry,pixels:{notch,caption,content,outside,sidebar}})
      check(geometry.style==='windows' && geometry.radius==='16px', name+' preserves the upstream inner radius')
      check(content[3]===255, name+' content stays opaque')
      if (!fullscreen && !maximized) check(outside[3]===0, name+' exterior corner stays transparent')
      if (sidebar!==undefined) check(sidebar[3]>0 && sidebar[3]<250, name+' sidebar stays translucent')
      if (cornerExpectHole) check(notch[3]===0, name+' reproduces the original transparent notch')
      else {
        check(notch[3]===255, name+' inner notch has opaque backing')
        // Chromium's solid-fill and gradient raster paths can differ by one sRGB step.
        if (!fullscreen) check(notch.every((value,index)=>Math.abs(value-caption[index])<=1), name+' backing matches the caption colour')
        check(geometry.backing!=='none', name+' backing follows the actual frame')
      }
    }
    const toggle = async collapsed => {
      const position=await page(`(() => {const r=document.querySelector('[data-sidebar-toggle]').getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};})()`)
      const point={x:Math.round(position.x),y:Math.round(position.y),button:'left',clickCount:1}
      window.webContents.sendInputEvent({type:'mouseDown',...point})
      window.webContents.sendInputEvent({type:'mouseUp',...point})
      await until(async () => (await page("!!document.querySelector('[data-sidebar-collapsed]')"))===collapsed)
      await cornerDelay(700)
    }
    try {
      await until(() => page("!!document.querySelector('div:has(> [class*=sidebarCol]) > [class*=centerCol]') && !!document.querySelector('[data-sidebar-toggle]')"))
      window.show(); window.focus()
      for (const dark of [false,true]) {
        await page(`document.body.toggleAttribute('data-ds-dark-theme',${dark})`)
        await capture(dark ? 'windows-corner-dark' : 'windows-corner-light')
      }
      if (!cornerExpectHole) {
        await toggle(true)
        await capture('windows-corner-collapsed',{collapsed:true})
        await toggle(false)
        window.maximize(); await until(() => window.isMaximized())
        await capture('windows-corner-maximized',{maximized:true})
        window.unmaximize(); await until(() => !window.isMaximized())
        await until(async () => (await page('innerWidth'))===1280)
        window.setFullScreen(true); await until(() => window.isFullScreen())
        await until(() => page("document.querySelector('dsh-kde-window-controls').hidden && document.querySelector('[class*=centerCol]').getBoundingClientRect().top===0"))
        await capture('windows-corner-fullscreen',{fullscreen:true})
      }
      await cornerFs.writeFile(cornerJoin(cornerOutput,'result.json'),JSON.stringify({ok:true,baseline:cornerExpectHole,records},null,2)+'\n')
      console.info('CLIENT_SMOKE COMPLETE corner pixels verified'); cornerElectron.app.quit()
    } catch (error) {
      await cornerFs.writeFile(cornerJoin(cornerOutput,'result.json'),JSON.stringify({ok:false,error:String(error.stack||error),records},null,2)+'\n')
      console.error('CLIENT_SMOKE FAIL '+error.stack); cornerElectron.app.exit(1)
    }
  })
})
setTimeout(() => { console.error('CLIENT_SMOKE FAIL corner timeout'); cornerElectron.app.exit(2) },60000).unref()
