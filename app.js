// Set dynamic copyright year
function setDynamicYear() {
    const yearElement = document.querySelector('.footer-year');
    if (yearElement) {
        yearElement.textContent = new Date().getFullYear();
    }
}

// Logo glitch animation functions
function initLogoGlitch() {
    if (typeof gsap === 'undefined') return;

    try {
        // Get all required elements
        const elements = {
            svg: document.querySelector('.svg'),
            paths: document.querySelectorAll('.mb-path'),
            logoGroup: document.getElementById('logoGroup')
        };

        if (!elements.svg || !elements.paths.length || !elements.logoGroup) return;

        // Add filter definition
        elements.svg.querySelector('defs').innerHTML = `
            <filter id="glitch">
                <feTurbulence id="glitchTurbulence" type="fractalNoise" baseFrequency="0 0" numOctaves="2" result="warp" />
                <feDisplacementMap id="glitchDisplacement" in="SourceGraphic" in2="warp" scale="0" xChannelSelector="R" yChannelSelector="G" result="displaced" />
                <feMorphology id="glitchDistortion" operator="erode" radius="0" in="displaced" result="distorted" />
                <feColorMatrix in="distorted" type="matrix" values="1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0" result="redChannel"/>
                <feOffset in="redChannel" dx="0" dy="0" result="r1"/>
                <feColorMatrix in="distorted" type="matrix" values="0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 1 0" result="greenChannel"/>
                <feOffset in="greenChannel" dx="0" dy="0" result="g1"/>
                <feColorMatrix in="distorted" type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 1 0" result="blueChannel"/>
                <feOffset in="blueChannel" dx="0" dy="0" result="b1"/>
                <feMerge>
                    <feMergeNode in="r1"/>
                    <feMergeNode in="g1"/>
                    <feMergeNode in="b1"/>
                </feMerge>
            </filter>
        `;

        // Get filter elements
        const filterElements = {
            turbulence: document.getElementById('glitchTurbulence'),
            displacement: document.getElementById('glitchDisplacement'),
            distortion: document.getElementById('glitchDistortion'),
            redShift: document.querySelector('feOffset[in="redChannel"]'),
            greenShift: document.querySelector('feOffset[in="greenChannel"]'),
            blueShift: document.querySelector('feOffset[in="blueChannel"]')
        };

        // Create and configure timeline
        const timeline = gsap.timeline({
            repeat: -1,
            repeatDelay: 7,
            paused: true
        });

        // Build animation sequence (using your exact timing)
        timeline
            .set(elements.logoGroup, { attr: { filter: 'url(#glitch)' } }, 0)
            .to(filterElements.turbulence, {
                duration: 0.5,
                attr: { baseFrequency: '0 0.3' }
            })
            .to(filterElements.displacement, {
                duration: 0.5,
                attr: { scale: '30' }
            }, 0)
            .to(elements.paths, {
                duration: 0.4,
                scaleY: 0.9,
                scaleX: 0.9,
                transformOrigin: 'center center'
            }, 0)
            .to(filterElements.distortion, {
                duration: 0.5,
                attr: { radius: 0.5 }
            }, 0)
            .to(filterElements.redShift, {
                duration: 0.5,
                attr: { dx: -5, dy: 0 }
            }, 0)
            .to(filterElements.greenShift, {
                duration: 0.5,
                attr: { dx: 5, dy: 0 }
            }, 0)
            .to(filterElements.blueShift, {
                duration: 0.5,
                attr: { dx: 0, dy: -5 }
            }, 0)
            .to(filterElements.turbulence, {
                duration: 0.5,
                attr: { baseFrequency: '0 25' }
            })
            .addLabel('end')
            .to(filterElements.turbulence, {
                duration: 0.5,
                attr: { baseFrequency: '0 0' }
            }, 'end')
            .to(filterElements.displacement, {
                duration: 0.5,
                attr: { scale: '0' }
            }, 'end')
            .to(elements.paths, {
                duration: 0.4,
                scaleY: 1,
                scaleX: 1,
                transformOrigin: 'center center'
            }, 'end')
            .to(filterElements.distortion, {
                duration: 0.5,
                attr: { radius: 0 }
            }, 'end')
            .to([filterElements.redShift, filterElements.greenShift, filterElements.blueShift], {
                duration: 0.5,
                attr: { dx: 0, dy: 0 }
            }, 'end')
            .call(() => elements.logoGroup.removeAttribute('filter'), null, 'end');

        // Store timeline reference and play
        window._logoGlitchTimeline = timeline;
        timeline.play();

    } catch (error) {
        console.error('Logo glitch initialization error:', error);
    }
}

function cleanupLogoGlitch() {
    if (window._logoGlitchTimeline) {
        window._logoGlitchTimeline.kill();
        delete window._logoGlitchTimeline;
    }
}

// Download button click handler
function initDownloadButtons() {
    const downloadBtns = document.querySelectorAll('.download-btn');
    downloadBtns.forEach(btn => {
        btn.addEventListener('click', () => {
            const url = btn.getAttribute('data-href');
            if (url) {
                window.location.href = url;
            }
        });
        
        btn.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                const url = btn.getAttribute('data-href');
                if (url) {
                    window.location.href = url;
                }
            }
        });
    });
}

// Fetch and display latest version from GitHub
async function fetchLatestVersion() {
    try {
        const response = await fetch('https://api.github.com/repos/misterburton/mb-lightroom-coach/releases/latest');
        if (!response.ok) return;
        
        const data = await response.json();
        const version = data.tag_name || '';
        
        if (version) {
            const cleanVersion = version.replace(/^v/, '');
            document.querySelectorAll('.download-version').forEach(el => {
                el.textContent = `(v${cleanVersion})`;
            });
        }
    } catch (e) {
        // Silently fail - version just won't show
    }
}

document.addEventListener('DOMContentLoaded', () => {
    setDynamicYear();
    initLogoGlitch();
    initDownloadButtons();
    fetchLatestVersion();
});

// Cleanup on page unload
window.addEventListener('beforeunload', cleanupLogoGlitch); 