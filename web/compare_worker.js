const MINOR_DE = 3.0;
const STRONG_DE = 6.0;
const CRITICAL_DE = 12.0;
const TILE_SIZE = 512;
const DEFECT_ZONE_SIZE = 64;

self.onmessage = async (event) => {
  const task = event.data;
  try {
    if (task.type === 'crop') {
      await cropImage(task);
      return;
    }
    if (task.type === 'compare') {
      await compareImages(task);
    }
  } catch (error) {
    self.postMessage({
      type: 'error',
      message: error instanceof Error ? error.message : String(error),
    });
  }
};

function progress(message) {
  self.postMessage({ type: 'progress', message });
}

async function decodeBitmap(value) {
  const bytes = value instanceof Uint8Array ? value : new Uint8Array(value);
  return createImageBitmap(new Blob([bytes]));
}

async function cropImage(task) {
  progress('Применяю границу обработки...');
  const bitmap = await decodeBitmap(task.image);
  const x = clamp(Math.round(task.x), 0, bitmap.width - 1);
  const y = clamp(Math.round(task.y), 0, bitmap.height - 1);
  const width = clamp(Math.round(task.width), 1, bitmap.width - x);
  const height = clamp(Math.round(task.height), 1, bitmap.height - y);
  const canvas = new OffscreenCanvas(width, height);
  const context = canvas.getContext('2d', { alpha: true });
  context.drawImage(bitmap, x, y, width, height, 0, 0, width, height);
  bitmap.close();
  const buffer = await canvasToPng(canvas);
  self.postMessage(
    { type: 'cropResult', bytes: buffer, width, height },
    [buffer],
  );
}

async function compareImages(task) {
  progress('Декодирую изображения в фоновом потоке...');
  const [refBitmap, cmpBitmap] = await Promise.all([
    decodeBitmap(task.reference),
    decodeBitmap(task.sample),
  ]);
  const width = refBitmap.width;
  const height = refBitmap.height;
  const refCanvas = new OffscreenCanvas(width, height);
  const cmpCanvas = new OffscreenCanvas(width, height);
  const refContext = refCanvas.getContext('2d', { alpha: true });
  const cmpContext = cmpCanvas.getContext('2d', { alpha: true });
  refContext.drawImage(refBitmap, 0, 0);
  cmpContext.drawImage(cmpBitmap, 0, 0, width, height);
  const refData = refContext.getImageData(0, 0, width, height);
  const cmpData = cmpContext.getImageData(0, 0, width, height);
  const sampleWidth = cmpBitmap.width;
  const sampleHeight = cmpBitmap.height;
  refBitmap.close();
  cmpBitmap.close();

  progress('Нормализую яркость...');
  normalizeLuminance(refData.data, cmpData.data);

  progress('Строю Lab-матрицы и контуры...');
  const refLab = buildLab(refData.data);
  const cmpLab = buildLab(cmpData.data);
  const refEdges = buildEdges(refData.data, width, height);
  const cmpEdges = buildEdges(cmpData.data, width, height);
  const shift = estimateResidualShift(
    refEdges.luma,
    cmpEdges.luma,
    refData.data,
    cmpData.data,
    width,
    height,
  );

  const pixelStep = clamp(Math.round(task.pixelStep || 1), 1, 4);
  const edgeRadius = clamp(Math.round(task.edgeTolerance || 0), 0, 6);
  const color = await compareColor({
    refData: refData.data,
    cmpData: cmpData.data,
    refLab,
    cmpLab,
    refMask: refEdges.mask,
    cmpMask: cmpEdges.mask,
    width,
    height,
    shift,
    pixelStep,
    edgeRadius,
  });

  let geometry = null;
  if (task.includeGeometry) {
    progress('Проверяю ЧБ геометрию...');
    geometry = await compareGeometry(
      refEdges.mask,
      cmpEdges.mask,
      width,
      height,
      shift,
    );
  }

  progress('Формирую карты сравнения...');
  const jobs = [imageDataToPng(color.map)];
  if (geometry) jobs.push(imageDataToPng(geometry.map));
  if (task.includeCanonical) {
    jobs.push(canvasToPng(refCanvas));
    cmpContext.putImageData(cmpData, 0, 0);
    jobs.push(canvasToPng(cmpCanvas));
  }
  const encoded = await Promise.all(jobs);
  let cursor = 0;
  const diffPng = encoded[cursor++];
  const geometryPng = geometry ? encoded[cursor++] : null;
  const refCanonical = task.includeCanonical ? encoded[cursor++] : null;
  const cmpCanonical = task.includeCanonical ? encoded[cursor++] : null;
  const totalPixels = color.validPixels || width * height;
  const meanDeltaE = color.deltaSum / totalPixels;
  const similarity = clamp((1 - clamp(meanDeltaE / CRITICAL_DE, 0, 1)) * 100, 0, 100);

  const result = {
    type: 'compareResult',
    similarity,
    diffPixels: color.diffPixels,
    totalPixels,
    refWidth: width,
    refHeight: height,
    sampleWidth,
    sampleHeight,
    meanDeltaE,
    maxDeltaE: color.maxDeltaE,
    defectZoneCount: color.defectZones.size,
    defectAreaPercent: totalPixels ? (color.diffPixels / totalPixels) * 100 : 0,
    diffPng,
    geometryScore: geometry ? geometry.score : null,
    geometryShiftPx: Math.hypot(shift.x, shift.y),
    geometryMissingPercent: geometry ? geometry.missingPercent : null,
    geometryExtraPercent: geometry ? geometry.extraPercent : null,
    geometryOverlapPixels: geometry ? geometry.overlap : null,
    geometryMissingPixels: geometry ? geometry.missing : null,
    geometryExtraPixels: geometry ? geometry.extra : null,
    geometryPng,
    refCanonical,
    cmpCanonical,
  };
  const transfers = [diffPng];
  if (geometryPng) transfers.push(geometryPng);
  if (refCanonical) transfers.push(refCanonical);
  if (cmpCanonical) transfers.push(cmpCanonical);
  self.postMessage(result, transfers);
}

async function compareColor(options) {
  const {
    refData,
    cmpData,
    refLab,
    cmpLab,
    refMask,
    cmpMask,
    width,
    height,
    shift,
    pixelStep,
    edgeRadius,
  } = options;
  const mapWidth = Math.ceil(width / pixelStep);
  const mapHeight = Math.ceil(height / pixelStep);
  const map = new ImageData(mapWidth, mapHeight);
  const zoneCols = Math.ceil(width / DEFECT_ZONE_SIZE);
  const defectZones = new Set();
  let deltaSum = 0;
  let maxDeltaE = 0;
  let diffPixels = 0;
  let validPixels = 0;
  const totalTiles = Math.ceil(width / TILE_SIZE) * Math.ceil(height / TILE_SIZE);
  let doneTiles = 0;

  for (let y0 = 0; y0 < height; y0 += TILE_SIZE) {
    const y1 = Math.min(height, y0 + TILE_SIZE);
    for (let x0 = 0; x0 < width; x0 += TILE_SIZE) {
      const x1 = Math.min(width, x0 + TILE_SIZE);
      for (let y = y0; y < y1; y += pixelStep) {
        for (let x = x0; x < x1; x += pixelStep) {
          const cx = x + shift.x;
          const cy = y + shift.y;
          if (cx < 0 || cy < 0 || cx >= width || cy >= height) continue;
          const refIndex = y * width + x;
          const cmpIndex = cy * width + cx;
          if (noData(refData, refIndex) || noData(cmpData, cmpIndex)) continue;
          const weight = Math.min(pixelStep, width - x) * Math.min(pixelStep, height - y);
          const delta = edgeAwareDeltaE({
            refLab,
            cmpLab,
            refMask,
            cmpMask,
            width,
            height,
            refIndex,
            cmpIndex,
            x,
            y,
            cx,
            cy,
            radius: edgeRadius,
          });
          deltaSum += delta * weight;
          maxDeltaE = Math.max(maxDeltaE, delta);
          validPixels += weight;
          if (delta >= MINOR_DE) diffPixels += weight;
          if (delta >= STRONG_DE) {
            defectZones.add(Math.floor(y / DEFECT_ZONE_SIZE) * zoneCols + Math.floor(x / DEFECT_ZONE_SIZE));
          }
          setDeltaPixel(map.data, Math.floor(y / pixelStep) * mapWidth + Math.floor(x / pixelStep), delta);
        }
      }
      doneTiles++;
      progress(
        pixelStep === 1
          ? `Точная Delta E: тайл ${doneTiles} / ${totalTiles}`
          : `Delta E уровня 2: тайл ${doneTiles} / ${totalTiles}`,
      );
      await Promise.resolve();
    }
  }
  return { map, deltaSum, maxDeltaE, diffPixels, validPixels, defectZones };
}

async function compareGeometry(refMask, cmpMask, width, height, shift) {
  const map = new ImageData(width, height);
  let refCount = 0;
  let cmpCount = 0;
  let overlap = 0;
  let missing = 0;
  let extra = 0;
  const reportStep = Math.max(64, Math.floor(height / 24));
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const index = y * width + x;
      const refHas = refMask[index] === 1;
      if (refHas) refCount++;
      const cx = x + shift.x;
      const cy = y + shift.y;
      const cmpHas = cx >= 0 && cy >= 0 && cx < width && cy < height && cmpMask[cy * width + cx] === 1;
      if (cmpHas) cmpCount++;
      if (refHas && cmpHas) {
        overlap++;
      } else if (refHas) {
        missing++;
        setRgba(map.data, index, 40, 90, 255, 210);
      } else if (cmpHas) {
        extra++;
        setRgba(map.data, index, 230, 30, 120, 210);
      }
    }
    if (y % reportStep === 0) {
      progress(`ЧБ геометрия: ${Math.round((y / Math.max(1, height)) * 100)}%`);
      await Promise.resolve();
    }
  }
  const union = refCount + cmpCount - overlap;
  return {
    map,
    score: union === 0 ? 100 : clamp((overlap / union) * 100, 0, 100),
    overlap,
    missing,
    extra,
    missingPercent: refCount === 0 ? 0 : (missing / refCount) * 100,
    extraPercent: cmpCount === 0 ? 0 : (extra / cmpCount) * 100,
  };
}

function normalizeLuminance(ref, cmp) {
  let refSum = 0;
  let cmpSum = 0;
  let refCount = 0;
  let cmpCount = 0;
  for (let i = 0; i < ref.length; i += 4) {
    if (ref[i + 3] >= 250) {
      refSum += lumaRgb(ref[i], ref[i + 1], ref[i + 2]);
      refCount++;
    }
    if (cmp[i + 3] >= 250) {
      cmpSum += lumaRgb(cmp[i], cmp[i + 1], cmp[i + 2]);
      cmpCount++;
    }
  }
  const refMean = refCount ? refSum / refCount : 0;
  const cmpMean = cmpCount ? cmpSum / cmpCount : 0;
  const scale = cmpMean < 1 ? 1 : refMean / cmpMean;
  if (Math.abs(scale - 1) < 0.001) return;
  for (let i = 0; i < cmp.length; i += 4) {
    cmp[i] = clamp(Math.round(cmp[i] * scale), 0, 255);
    cmp[i + 1] = clamp(Math.round(cmp[i + 1] * scale), 0, 255);
    cmp[i + 2] = clamp(Math.round(cmp[i + 2] * scale), 0, 255);
  }
}

function buildLab(data) {
  const pixels = data.length / 4;
  const lab = new Float32Array(pixels * 3);
  for (let i = 0; i < pixels; i++) {
    const p = i * 4;
    const r = pivotRgb(data[p]);
    const g = pivotRgb(data[p + 1]);
    const b = pivotRgb(data[p + 2]);
    const x = (r * 0.4124564 + g * 0.3575761 + b * 0.1804375) / 0.95047;
    const y = r * 0.2126729 + g * 0.7151522 + b * 0.0721750;
    const z = (r * 0.0193339 + g * 0.1191920 + b * 0.9503041) / 1.08883;
    const fx = pivotXyz(x);
    const fy = pivotXyz(y);
    const fz = pivotXyz(z);
    const q = i * 3;
    lab[q] = 116 * fy - 16;
    lab[q + 1] = 500 * (fx - fy);
    lab[q + 2] = 200 * (fy - fz);
  }
  return lab;
}

function buildEdges(data, width, height) {
  const pixels = width * height;
  const luma = new Float32Array(pixels);
  const gradients = new Float32Array(pixels);
  const mask = new Uint8Array(pixels);
  for (let i = 0; i < pixels; i++) {
    const p = i * 4;
    luma[i] = lumaRgb(data[p], data[p + 1], data[p + 2]);
  }
  let sum = 0;
  let maxGradient = 0;
  let count = 0;
  for (let y = 1; y < height - 1; y++) {
    for (let x = 1; x < width - 1; x++) {
      const i = y * width + x;
      const gradient = Math.abs(luma[i + 1] - luma[i - 1]) + Math.abs(luma[i + width] - luma[i - width]);
      gradients[i] = gradient;
      sum += gradient;
      maxGradient = Math.max(maxGradient, gradient);
      count++;
    }
  }
  const mean = count ? sum / count : 0;
  const threshold = Math.max(18, mean * 2.4, maxGradient * 0.16);
  for (let y = 1; y < height - 1; y++) {
    for (let x = 1; x < width - 1; x++) {
      const i = y * width + x;
      if (!noData(data, i) && gradients[i] >= threshold) mask[i] = 1;
    }
  }
  return { luma, mask };
}

function estimateResidualShift(refLuma, cmpLuma, refData, cmpData, width, height) {
  const maxDim = Math.max(width, height);
  const sampleStep = Math.max(1, Math.round(maxDim / 260));
  const maxAccepted = Math.max(4, Math.round(maxDim / 450));
  const radius = Math.max(4, Math.min(12, maxAccepted + 2));
  const margin = radius + sampleStep * 2;
  let bestScore = Infinity;
  let bestX = 0;
  let bestY = 0;
  for (let dy = -radius; dy <= radius; dy++) {
    for (let dx = -radius; dx <= radius; dx++) {
      let score = 0;
      let count = 0;
      for (let y = margin; y < height - margin; y += sampleStep) {
        const cy = y + dy;
        for (let x = margin; x < width - margin; x += sampleStep) {
          const cx = x + dx;
          const ri = y * width + x;
          const ci = cy * width + cx;
          if (noData(refData, ri) || noData(cmpData, ci)) continue;
          score += Math.abs(refLuma[ri] - cmpLuma[ci]);
          count++;
        }
      }
      if (count && score / count < bestScore) {
        bestScore = score / count;
        bestX = dx;
        bestY = dy;
      }
    }
  }
  return Math.abs(bestX) <= maxAccepted && Math.abs(bestY) <= maxAccepted
    ? { x: bestX, y: bestY }
    : { x: 0, y: 0 };
}

function edgeAwareDeltaE(options) {
  const raw = labDelta(options.refLab, options.refIndex, options.cmpLab, options.cmpIndex);
  if (options.radius <= 0 || raw < MINOR_DE) return raw;
  const nearRef = edgeNear(options.refMask, options.width, options.height, options.x, options.y, options.radius);
  const nearCmp = edgeNear(options.cmpMask, options.width, options.height, options.cx, options.cy, options.radius);
  if (!nearRef && !nearCmp) return raw;
  const local = Math.min(
    minLocalDelta(options.refLab, options.refIndex, options.cmpLab, options.width, options.height, options.cx, options.cy, options.radius),
    minLocalDelta(options.cmpLab, options.cmpIndex, options.refLab, options.width, options.height, options.x, options.y, options.radius),
  );
  let corrected = Math.min(raw, local);
  if (nearRef && nearCmp && local < raw) corrected *= 0.42;
  return corrected;
}

function minLocalDelta(sourceLab, sourceIndex, targetLab, width, height, cx, cy, radius) {
  let best = Infinity;
  for (let y = Math.max(0, cy - radius); y <= Math.min(height - 1, cy + radius); y++) {
    for (let x = Math.max(0, cx - radius); x <= Math.min(width - 1, cx + radius); x++) {
      best = Math.min(best, labDelta(sourceLab, sourceIndex, targetLab, y * width + x));
    }
  }
  return best;
}

function edgeNear(mask, width, height, cx, cy, radius) {
  for (let y = Math.max(1, cy - radius); y <= Math.min(height - 2, cy + radius); y++) {
    for (let x = Math.max(1, cx - radius); x <= Math.min(width - 2, cx + radius); x++) {
      if (mask[y * width + x] === 1) return true;
    }
  }
  return false;
}

function labDelta(a, ai, b, bi) {
  const ap = ai * 3;
  const bp = bi * 3;
  const dl = a[ap] - b[bp];
  const da = a[ap + 1] - b[bp + 1];
  const db = a[ap + 2] - b[bp + 2];
  return Math.sqrt(dl * dl + da * da + db * db);
}

function setDeltaPixel(data, index, delta) {
  if (delta < MINOR_DE) return;
  if (delta < STRONG_DE) {
    const alpha = Math.round(((delta - MINOR_DE) / (STRONG_DE - MINOR_DE)) * 210);
    setRgba(data, index, 30, 210, 30, alpha);
  } else if (delta < CRITICAL_DE) {
    const alpha = clamp(Math.round(180 + ((delta - STRONG_DE) / (CRITICAL_DE - STRONG_DE)) * 50), 0, 230);
    setRgba(data, index, 255, 170, 0, alpha);
  } else {
    setRgba(data, index, 240, 20, 20, 230);
  }
}

function setRgba(data, index, r, g, b, a) {
  const p = index * 4;
  data[p] = r;
  data[p + 1] = g;
  data[p + 2] = b;
  data[p + 3] = a;
}

function noData(data, pixelIndex) {
  return data[pixelIndex * 4 + 3] < 250;
}

function lumaRgb(r, g, b) {
  return r * 0.299 + g * 0.587 + b * 0.114;
}

function pivotRgb(value) {
  const c = value / 255;
  return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

function pivotXyz(value) {
  return value > 0.008856 ? Math.pow(value, 1 / 3) : 7.787 * value + 16 / 116;
}

async function imageDataToPng(imageData) {
  const canvas = new OffscreenCanvas(imageData.width, imageData.height);
  canvas.getContext('2d', { alpha: true }).putImageData(imageData, 0, 0);
  return canvasToPng(canvas);
}

async function canvasToPng(canvas) {
  const blob = await canvas.convertToBlob({ type: 'image/png' });
  return blob.arrayBuffer();
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}
