// SPDX-License-Identifier: GPL-3.0-or-later
// Input arrives only through WKWebView.callAsyncJavaScript arguments.
window.nodebayRenderDiagram = async function (source, dark) {
    if (typeof source !== 'string' || source.length > 20000 || source.split('\n').length > 300) {
        throw new Error('Diagram exceeds preview limits');
    }
    // Preview documents cannot change the renderer's security, styles or resource policy.
    if (/%%\s*\{|^\s*---(?:\r?\n|$)/m.test(source)) {
        throw new Error('Diagram configuration directives are not supported in previews');
    }
    const holder = document.getElementById('diagram');
    holder.replaceChildren();
    // Mermaid 12 defaults individual diagrams to the shaded "neo" look. Keep
    // document diagrams flat and consistent with the native reading surface.
    const colors = dark
        ? { text: '#E9E9EB', fill: '#28282C', border: '#99999F', line: '#BBBBBF', surface: '#202023' }
        : { text: '#242426', fill: '#F4F4F6', border: '#7D7D83', line: '#64646B', surface: '#FFFFFF' };
    const flatStyles = `
        * { filter: none !important; box-shadow: none !important; }
        .node rect, .node polygon, .node circle, .node ellipse, .node path,
        .cluster rect, rect.actor, .note, .labelBox, .activation0,
        .activation1, .activation2, .loopLine {
            stroke-width: 1px !important;
        }
        .flowchart-link, .messageLine0, .messageLine1, .actor-line {
            stroke-width: 1px !important;
        }
    `;
    mermaid.initialize({
        startOnLoad: false,
        securityLevel: 'strict',
        suppressErrorRendering: true,
        htmlLabels: false,
        theme: 'base',
        look: 'classic',
        themeVariables: {
            darkMode: dark, background: colors.surface,
            primaryColor: colors.fill, primaryTextColor: colors.text,
            primaryBorderColor: colors.border, secondaryColor: colors.fill,
            secondaryTextColor: colors.text, secondaryBorderColor: colors.border,
            tertiaryColor: colors.fill, tertiaryTextColor: colors.text,
            tertiaryBorderColor: colors.border, mainBkg: colors.fill,
            nodeBorder: colors.border, nodeTextColor: colors.text,
            lineColor: colors.line, textColor: colors.text,
            actorBkg: colors.fill, actorBorder: colors.border,
            actorTextColor: colors.text, actorLineColor: colors.line,
            signalColor: colors.line, signalTextColor: colors.text,
            labelBoxBkgColor: colors.fill, labelBoxBorderColor: colors.border,
            labelTextColor: colors.text, loopTextColor: colors.text,
            noteBkgColor: colors.fill, noteBorderColor: colors.border,
            noteTextColor: colors.text, edgeLabelBackground: colors.surface,
            clusterBkg: colors.fill, clusterBorder: colors.border,
            activationBkgColor: colors.fill, activationBorderColor: colors.border,
            strokeWidth: 1, useGradient: false, dropShadow: 'none'
        },
        themeCSS: flatStyles,
        fontFamily: 'Arial, sans-serif',
        layout: 'dagre',
        maxTextSize: 20000,
        maxEdges: 200,
        flowchart: { htmlLabels: false, useMaxWidth: false, look: 'classic' },
        sequence: { useMaxWidth: false, look: 'classic' },
        secure: ['securityLevel', 'startOnLoad', 'maxTextSize', 'maxEdges', 'suppressErrorRendering',
                 'htmlLabels', 'fontFamily', 'theme', 'themeVariables', 'themeCSS', 'flowchart', 'sequence', 'look', 'layout']
    });
    const result = await mermaid.render('nodebayDiagram', source, holder);
    const parsed = new DOMParser().parseFromString(result.svg, 'image/svg+xml');
    const svg = parsed.documentElement;
    if (svg.localName !== 'svg' || parsed.querySelector('parsererror') || svg.querySelectorAll('*').length > 5000) {
        throw new Error('Unsupported diagram output');
    }
    // A raster attachment has no scripts, links, embedded HTML, or resource loading.
    if (svg.querySelector('foreignObject,script,iframe,object,embed,image')) {
        throw new Error('Embedded diagram resources are not supported');
    }
    for (const filter of svg.querySelectorAll('filter')) filter.remove();
    for (const element of [svg, ...svg.querySelectorAll('*')]) {
        element.removeAttribute('filter');
        for (const attribute of [...element.attributes]) {
            if (/^on/i.test(attribute.name)) element.removeAttributeNode(attribute);
            else if (attribute.localName === 'href' && !attribute.value.startsWith('#')) element.removeAttributeNode(attribute);
            else if (/@import|url\(\s*["']?(?!#)/i.test(attribute.value)) {
                throw new Error('External diagram styles are not supported');
            }
        }
    }
    for (const style of svg.querySelectorAll('style')) {
        if (/@import|url\(\s*["']?(?!#)/i.test(style.textContent)) throw new Error('External diagram styles are not supported');
    }
    const box = (svg.getAttribute('viewBox') || '').trim().split(/[\s,]+/).map(Number);
    if (box.length !== 4 || !box.every(Number.isFinite) || box[2] <= 0 || box[3] <= 0 || box[2] > 20000 || box[3] > 20000) {
        throw new Error('Invalid diagram dimensions');
    }
    const width = Math.ceil(box[2]), height = Math.ceil(box[3]);
    // Preserve 2x text where possible; cap either raster dimension and total allocation.
    const scale = Math.min(2, 2048 / width, 2048 / height, Math.sqrt(4000000 / (width * height)));
    const pixelWidth = Math.max(1, Math.floor(width * scale));
    const pixelHeight = Math.max(1, Math.floor(height * scale));
    svg.setAttribute('width', String(width));
    svg.setAttribute('height', String(height));
    svg.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
    const serialized = new XMLSerializer().serializeToString(svg);
    if (serialized.length > 2000000) throw new Error('Diagram exceeds preview limits');
    const image = new Image();
    await new Promise((resolve, reject) => {
        image.onload = resolve;
        image.onerror = () => reject(new Error('Diagram image could not be decoded'));
        image.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(serialized);
    });
    const canvas = document.createElement('canvas');
    canvas.width = pixelWidth;
    canvas.height = pixelHeight;
    const context = canvas.getContext('2d');
    if (!context) throw new Error('Diagram rasterizer unavailable');
    context.drawImage(image, 0, 0, pixelWidth, pixelHeight);
    const png = canvas.toDataURL('image/png');
    holder.replaceChildren();
    return { png: png.slice(png.indexOf(',') + 1), width, height };
};
