import vertexShaderSource from './src/shaders/vertex.glsl?raw';
import fragmentShaderSource from './src/shaders/fragment.glsl?raw';

const canvas = document.getElementById('glcanvas');
const gl = canvas.getContext('webgl2');

if (!gl) {
    alert('WebGL 2 is not supported by your browser. Please try another browser.');
}

// ----------------------------------------------------
// Shader Compilation and Program Setup
// ----------------------------------------------------
function compileShader(gl, type, source) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        console.error('Shader compilation error:', gl.getShaderInfoLog(shader));
        gl.deleteShader(shader);
        return null;
    }
    return shader;
}

const vertexShader = compileShader(gl, gl.VERTEX_SHADER, vertexShaderSource);
const fragmentShader = compileShader(gl, gl.FRAGMENT_SHADER, fragmentShaderSource);

const program = gl.createProgram();
gl.attachShader(program, vertexShader);
gl.attachShader(program, fragmentShader);
gl.linkProgram(program);

if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    console.error('Program linking error:', gl.getProgramInfoLog(program));
}

// ----------------------------------------------------
// Geometry Setup (Full Screen Quad)
// ----------------------------------------------------
const positionBuffer = gl.createBuffer();
gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
// Define 4 vertices for a quad that covers the entire screen [-1, 1]
const positions = new Float32Array([
    -1.0, -1.0,
     1.0, -1.0,
    -1.0,  1.0,
     1.0,  1.0,
]);
gl.bufferData(gl.ARRAY_BUFFER, positions, gl.STATIC_DRAW);

// ----------------------------------------------------
// Attributes & Uniforms Configuration
// ----------------------------------------------------
const positionAttributeLocation = gl.getAttribLocation(program, 'a_position');
const timeUniformLocation = gl.getUniformLocation(program, 'u_time');
const resolutionUniformLocation = gl.getUniformLocation(program, 'u_resolution');
const texUniformLocation = gl.getUniformLocation(program, 'u_tex');
const modeUniformLocation = gl.getUniformLocation(program, 'u_mode');
const centerUniformLocation = gl.getUniformLocation(program, 'u_center');
const radiusUniformLocation = gl.getUniformLocation(program, 'u_radius');
const animateUniformLocation = gl.getUniformLocation(program, 'u_animate');
const angleUniformLocation = gl.getUniformLocation(program, 'u_angle');
const glowUniformLocation = gl.getUniformLocation(program, 'u_glow');
const wispUniformLocation = gl.getUniformLocation(program, 'u_wisp');

// Create and bind Vertex Array Object (VAO)
const vao = gl.createVertexArray();
gl.bindVertexArray(vao);
gl.enableVertexAttribArray(positionAttributeLocation);
// Bind the position buffer to the a_position attribute
gl.vertexAttribPointer(positionAttributeLocation, 2, gl.FLOAT, false, 0, 0);

// ----------------------------------------------------
// Texture Initialization
// ----------------------------------------------------
const texture = gl.createTexture();
gl.bindTexture(gl.TEXTURE_2D, texture);
// Provide a 1x1 default black texture before user uploads an image
gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([0, 0, 0, 255]));

// ----------------------------------------------------
// State and Event Listeners
// ----------------------------------------------------
let currentMode = 0;
const startTime = performance.now();
let uCenter = [0.5, 0.5];
let uRadius = [0.5, 0.5];
let uAngle = 0.0;
let uGlow = 0.3; // Default 30 / 100
let uWisp = 4.0; // Default 400 / 100
let isAnimating = 0; // 0 = false, 1 = true

const interactionPrompt = document.getElementById('interaction-prompt');
const applyBtn = document.getElementById('apply-btn');
const rotationControl = document.getElementById('rotation-control');
const rotationSlider = document.getElementById('rotation-slider');
const glowControl = document.getElementById('glow-control');
const glowSlider = document.getElementById('glow-slider');
const wispControl = document.getElementById('wisp-control');
const wispSlider = document.getElementById('wisp-slider');
const wispValueDisplay = document.getElementById('wisp-value');

rotationSlider.addEventListener('input', (e) => {
    uAngle = (parseFloat(e.target.value) * Math.PI) / 180.0;
    const selectionCircle = document.getElementById('selection-circle');
    selectionCircle.style.transform = `translate(-50%,-50%) rotate(${e.target.value}deg)`;
});

glowSlider.addEventListener('input', (e) => {
    uGlow = parseFloat(e.target.value) / 100.0;
});

wispSlider.addEventListener('input', (e) => {
    uWisp = parseFloat(e.target.value) / 100.0;
    wispValueDisplay.innerText = uWisp.toFixed(1);
});

const resetBtn = document.getElementById('reset-btn');
resetBtn.addEventListener('click', () => {
    isAnimating = 0;
    uCenter = [0.5, 0.5];
    uRadius = [0.5, 0.5];
    uAngle = 0.0;
    rotationSlider.value = 0;
    const selectionCircle = document.getElementById('selection-circle');
    selectionCircle.style.transform = `translate(-50%,-50%) rotate(0deg)`;
    selectionCircle.style.display = 'none';
    
    if (currentMode === 0) {
        interactionPrompt.classList.remove('hidden');
        rotationControl.classList.remove('hidden');
        applyBtn.classList.add('hidden');
    }
});

// Image Upload Handler
const imageUpload = document.getElementById('image-upload');
imageUpload.addEventListener('change', (e) => {
    const file = e.target.files[0];
    if (file) {
        const reader = new FileReader();
        reader.onload = (event) => {
            const img = new Image();
            img.onload = () => {
                gl.bindTexture(gl.TEXTURE_2D, texture);
                
                // WebGL expects the bottom-left corner to be the origin, flip Y
                gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
                
                // Adjust canvas to match original image size exactly
                setCanvasSize(img.width, img.height);
                
                // Upload image to GPU
                gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, img);
                
                // Generate mipmaps for smooth luminance sampling in the shader
                gl.generateMipmap(gl.TEXTURE_2D);
                // Set texture wrapping and filtering
                gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
                gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
                gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
                gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
                
                // Show prompt if Galaxy mode
                if (currentMode === 0) {
                    interactionPrompt.classList.remove('hidden');
                    rotationControl.classList.remove('hidden');
                    glowControl.classList.remove('hidden');
                    wispControl.classList.remove('hidden');
                    isAnimating = 0;
                } else {
                    isAnimating = 1;
                }
                resetBtn.classList.remove('hidden');
            };
            img.src = event.target.result;
        };
        reader.readAsDataURL(file);
    }
});

// Mode Selector Handler
const modeSelect = document.getElementById('mode-select');
const instruction = document.getElementById('mode-instruction');
modeSelect.addEventListener('change', (e) => {
    currentMode = parseInt(e.target.value, 10);
    isAnimating = 1; // Default to animate for other modes
    interactionPrompt.classList.add('hidden');
    applyBtn.classList.add('hidden');
    rotationControl.classList.add('hidden');
    glowControl.classList.add('hidden');
    wispControl.classList.add('hidden');
    
    if (currentMode === 0) {
        instruction.textContent = "Click and drag from the center of the galaxy outwards to define its elliptical shape.";
        isAnimating = 0; // Pause for setup
        interactionPrompt.classList.remove('hidden');
        if (texture) {
            rotationControl.classList.remove('hidden');
            glowControl.classList.remove('hidden');
            wispControl.classList.remove('hidden');
        }
    } else if (currentMode === 1) {
        instruction.textContent = "Watch the bright nebula gases drift based on their luminance.";
    } else if (currentMode === 2) {
        instruction.textContent = "The image is mathematically spherized into a rotating planet.";
    }
});

// Interaction for Galaxy Swirl
const selectionCircle = document.getElementById('selection-circle');
let isDragging = false;
let startPos = {x: 0, y: 0};

canvas.addEventListener('mousedown', (e) => {
    // Get mouse pos relative to canvas, not window
    const rect = canvas.getBoundingClientRect();
    if (currentMode !== 0 || isAnimating === 1) return;
    
    isDragging = true;
    startPos.x = e.clientX - rect.left;
    startPos.y = e.clientY - rect.top;
    
    // Hide prompt while dragging
    interactionPrompt.classList.add('hidden');
    applyBtn.classList.add('hidden');
    
    // UV space goes from 0 at left/bottom to 1 at right/top (WebGL flips Y)
    uCenter[0] = startPos.x / rect.width;
    uCenter[1] = 1.0 - (startPos.y / rect.height);
    uRadius = [0.0, 0.0];
    
    selectionCircle.style.display = 'block';
    selectionCircle.style.left = `${e.clientX}px`;
    selectionCircle.style.top = `${e.clientY}px`;
    selectionCircle.style.width = '0px';
    selectionCircle.style.height = '0px';
});

window.addEventListener('mousemove', (e) => {
    if (!isDragging) return;
    const rect = canvas.getBoundingClientRect();
    const currentX = e.clientX - rect.left;
    const currentY = e.clientY - rect.top;
    
    const dx = Math.abs(currentX - startPos.x);
    const dy = Math.abs(currentY - startPos.y);
    
    selectionCircle.style.width = `${dx * 2}px`;
    selectionCircle.style.height = `${dy * 2}px`;
    
    // Convert px radius to our shader's [-1, 1] aspect-corrected coordinate space distance.
    const aspect = canvas.width / canvas.height;
    uRadius[0] = (dx / rect.width) * (2.0 * aspect);
    uRadius[1] = (dy / rect.height) * 2.0;
});

window.addEventListener('mouseup', () => {
    if (isDragging) {
        isDragging = false;
        // Show apply button
        applyBtn.classList.remove('hidden');
    }
});

applyBtn.addEventListener('click', () => {
    isAnimating = 1;
    applyBtn.classList.add('hidden');
    selectionCircle.style.display = 'none';
});

// Size Canvas Function
function setCanvasSize(w, h) {
    canvas.width = w;
    canvas.height = h;
    gl.viewport(0, 0, w, h);
}
// Initial default size
setCanvasSize(window.innerWidth, window.innerHeight);

// ----------------------------------------------------
// Render Loop
// ----------------------------------------------------
function render() {
    // 3. Clear canvas
    gl.clearColor(0.0, 0.0, 0.0, 1.0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    
    // 4. Use Shader Program and VAO
    gl.useProgram(program);
    gl.bindVertexArray(vao);
    
    // 5. Update Uniforms
    const elapsedTime = (performance.now() - startTime) / 1000.0; // Seconds
    gl.uniform1f(timeUniformLocation, elapsedTime);
    gl.uniform2f(resolutionUniformLocation, gl.canvas.width, gl.canvas.height);
    gl.uniform1i(modeUniformLocation, currentMode);
    gl.uniform2fv(centerUniformLocation, uCenter);
    gl.uniform2fv(radiusUniformLocation, uRadius); // Now a 2fv
    gl.uniform1f(angleUniformLocation, uAngle);
    gl.uniform1f(glowUniformLocation, uGlow);
    gl.uniform1f(wispUniformLocation, uWisp);
    gl.uniform1i(animateUniformLocation, isAnimating);
    
    // 6. Bind Texture to Texture Unit 0
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.uniform1i(texUniformLocation, 0);
    
    // 7. Draw the Quad
    // TRIANGLE_STRIP with 4 vertices will draw a full-screen rectangle
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    
    // 8. Loop
    requestAnimationFrame(render);
}

// Start rendering
requestAnimationFrame(render);
