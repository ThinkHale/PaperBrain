/**
 * annotate.js — Canvas annotation engine for Illuminote
 *
 * Usage:
 *   const engine = new AnnotationEngine(canvasEl, imageEl, { onSave, onDelete });
 *   engine.setTool('rect' | 'ellipse' | 'freehand');
 *   engine.setTag('equations');
 *   engine.setColor('#FFC857');
 *   engine.loadAnnotations(rows);   // from Supabase
 *   engine.destroy();
 *
 * Coordinates are stored normalized (0-1) relative to the image dimensions
 * so they stay correct at any display size.
 */

const TAG_COLORS = [
  "#FFC857", "#5B6472", "#E6E8EF", "#10b981",
  "#3b82f6", "#ef4444", "#8b5cf6", "#14b8a6",
];

let _colorIndex = 0;
const _tagColorMap = new Map();

export function colorForTag(tag) {
  if (!_tagColorMap.has(tag)) {
    _tagColorMap.set(tag, TAG_COLORS[_colorIndex % TAG_COLORS.length]);
    _colorIndex++;
  }
  return _tagColorMap.get(tag);
}

export class AnnotationEngine {
  /**
   * @param {HTMLCanvasElement} canvas
   * @param {HTMLImageElement}  image
   * @param {{ onSave?: fn, onDelete?: fn, onSelect?: fn }} opts
   */
  constructor(canvas, image, opts = {}) {
    this.canvas = canvas;
    this.image = image;
    this.opts = opts;
    this.tool = "rect";
    this.tag = "";
    this.color = TAG_COLORS[0];
    this.annotations = [];   // { id?, shape_type, shape_data, tag, label, color }
    this.selected = null;    // index into this.annotations

    // Drawing state
    this._drawing = false;
    this._startX = 0;
    this._startY = 0;
    this._currentPoints = [];

    this._bindEvents();
    this._resizeObserver = new ResizeObserver(() => this._resizeCanvas());
    this._resizeObserver.observe(image);
    this._resizeCanvas();
  }

  setTool(tool) { this.tool = tool; }
  setTag(tag) {
    this.tag = tag;
    this.color = colorForTag(tag) || this.color;
  }
  setColor(color) { this.color = color; }

  loadAnnotations(rows) {
    this.annotations = rows.map((r) => ({ ...r }));
    this._draw();
  }

  destroy() {
    this._unbindEvents();
    this._resizeObserver.disconnect();
  }

  // ── Private: canvas sizing ──────────────────────────────────

  _resizeCanvas() {
    const rect = this.image.getBoundingClientRect();
    this.canvas.width = rect.width;
    this.canvas.height = rect.height;
    this._draw();
  }

  /** Convert clientX/Y to normalized coords (0-1) relative to the image. */
  _toNorm(clientX, clientY) {
    const rect = this.canvas.getBoundingClientRect();
    return {
      x: (clientX - rect.left) / rect.width,
      y: (clientY - rect.top) / rect.height,
    };
  }

  /** Convert normalized coords to canvas pixels. */
  _toPx(nx, ny) {
    return { x: nx * this.canvas.width, y: ny * this.canvas.height };
  }

  // ── Private: events ─────────────────────────────────────────

  _bindEvents() {
    this._onDown  = (e) => this._handleDown(e);
    this._onMove  = (e) => this._handleMove(e);
    this._onUp    = (e) => this._handleUp(e);
    this._onClick = (e) => this._handleClick(e);

    this.canvas.addEventListener("mousedown",  this._onDown);
    this.canvas.addEventListener("mousemove",  this._onMove);
    this.canvas.addEventListener("mouseup",    this._onUp);
    this.canvas.addEventListener("touchstart", this._onDown, { passive: false });
    this.canvas.addEventListener("touchmove",  this._onMove, { passive: false });
    this.canvas.addEventListener("touchend",   this._onUp);
    this.canvas.addEventListener("click",      this._onClick);
  }

  _unbindEvents() {
    this.canvas.removeEventListener("mousedown",  this._onDown);
    this.canvas.removeEventListener("mousemove",  this._onMove);
    this.canvas.removeEventListener("mouseup",    this._onUp);
    this.canvas.removeEventListener("touchstart", this._onDown);
    this.canvas.removeEventListener("touchmove",  this._onMove);
    this.canvas.removeEventListener("touchend",   this._onUp);
    this.canvas.removeEventListener("click",      this._onClick);
  }

  _getEventPos(e) {
    if (e.touches) {
      e.preventDefault();
      return { clientX: e.touches[0].clientX, clientY: e.touches[0].clientY };
    }
    return { clientX: e.clientX, clientY: e.clientY };
  }

  _handleDown(e) {
    const { clientX, clientY } = this._getEventPos(e);
    const norm = this._toNorm(clientX, clientY);
    this._drawing = true;
    this._startX = norm.x;
    this._startY = norm.y;
    if (this.tool === "freehand") {
      this._currentPoints = [[norm.x, norm.y]];
    }
  }

  _handleMove(e) {
    if (!this._drawing) return;
    const { clientX, clientY } = this._getEventPos(e);
    const norm = this._toNorm(clientX, clientY);

    if (this.tool === "freehand") {
      this._currentPoints.push([norm.x, norm.y]);
    }
    this._draw(norm);
  }

  _handleUp(e) {
    if (!this._drawing) return;
    this._drawing = false;

    const { clientX, clientY } = this._getEventPos(e);
    const norm = this._toNorm(clientX, clientY);

    let shape_data;
    if (this.tool === "rect") {
      const x = Math.min(this._startX, norm.x);
      const y = Math.min(this._startY, norm.y);
      const w = Math.abs(norm.x - this._startX);
      const h = Math.abs(norm.y - this._startY);
      if (w < 0.01 || h < 0.01) { this._draw(); return; }
      shape_data = { x, y, w, h };
    } else if (this.tool === "ellipse") {
      const cx = (this._startX + norm.x) / 2;
      const cy = (this._startY + norm.y) / 2;
      const rx = Math.abs(norm.x - this._startX) / 2;
      const ry = Math.abs(norm.y - this._startY) / 2;
      if (rx < 0.01 || ry < 0.01) { this._draw(); return; }
      shape_data = { cx, cy, rx, ry };
    } else {
      if (this._currentPoints.length < 3) { this._draw(); return; }
      shape_data = { points: this._currentPoints };
    }

    const ann = {
      shape_type: this.tool,
      shape_data,
      tag: this.tag,
      label: this.tag,
      color: this.color,
    };
    this.annotations.push(ann);
    this._draw();

    if (this.opts.onSave) {
      this.opts.onSave(ann).then((saved) => {
        // Back-fill the id from Supabase
        const idx = this.annotations.indexOf(ann);
        if (idx !== -1 && saved?.id) this.annotations[idx].id = saved.id;
      });
    }
  }

  _handleClick(e) {
    if (this._drawing) return;
    const { clientX, clientY } = this._getEventPos(e);
    const norm = this._toNorm(clientX, clientY);
    const hit = this._hitTest(norm.x, norm.y);
    this.selected = hit;
    this._draw();
    if (this.opts.onSelect) this.opts.onSelect(hit !== null ? this.annotations[hit] : null);
  }

  // ── Private: hit testing ────────────────────────────────────

  _hitTest(nx, ny) {
    for (let i = this.annotations.length - 1; i >= 0; i--) {
      const a = this.annotations[i];
      const d = a.shape_data;
      if (a.shape_type === "rect") {
        if (nx >= d.x && nx <= d.x + d.w && ny >= d.y && ny <= d.y + d.h) return i;
      } else if (a.shape_type === "ellipse") {
        const dx = (nx - d.cx) / (d.rx || 0.001);
        const dy = (ny - d.cy) / (d.ry || 0.001);
        if (dx * dx + dy * dy <= 1) return i;
      } else if (a.shape_type === "freehand") {
        // Hit test: is point within 0.02 of any segment
        const pts = d.points;
        for (let j = 0; j < pts.length - 1; j++) {
          const dist = _ptSegDist(nx, ny, pts[j][0], pts[j][1], pts[j+1][0], pts[j+1][1]);
          if (dist < 0.02) return i;
        }
      }
    }
    return null;
  }

  // ── Public: delete selected ─────────────────────────────────

  deleteSelected() {
    if (this.selected === null) return;
    const ann = this.annotations[this.selected];
    this.annotations.splice(this.selected, 1);
    this.selected = null;
    this._draw();
    if (ann.id && this.opts.onDelete) this.opts.onDelete(ann.id);
  }

  /** Crop the bounding box of the selected annotation from the source image. */
  async cropSelected(imageDataUrl) {
    if (this.selected === null) return null;
    const ann = this.annotations[this.selected];
    const d = ann.shape_data;
    let rect;
    if (ann.shape_type === "rect") {
      rect = d;
    } else if (ann.shape_type === "ellipse") {
      rect = { x: d.cx - d.rx, y: d.cy - d.ry, w: d.rx * 2, h: d.ry * 2 };
    } else {
      const xs = d.points.map((p) => p[0]);
      const ys = d.points.map((p) => p[1]);
      const minX = Math.min(...xs), maxX = Math.max(...xs);
      const minY = Math.min(...ys), maxY = Math.max(...ys);
      rect = { x: minX, y: minY, w: maxX - minX, h: maxY - minY };
    }
    const { cropImage } = await import("./api.js");
    return cropImage(imageDataUrl, rect);
  }

  // ── Private: drawing ────────────────────────────────────────

  _draw(liveNorm) {
    const ctx = this.canvas.getContext("2d");
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

    // Draw saved annotations
    this.annotations.forEach((a, i) => {
      this._drawShape(ctx, a, i === this.selected);
    });

    // Draw in-progress shape
    if (this._drawing && liveNorm) {
      const ghost = {
        shape_type: this.tool,
        color: this.color,
        shape_data: this._liveShapeData(liveNorm),
      };
      if (ghost.shape_data) this._drawShape(ctx, ghost, false, 0.5);
    }
  }

  _liveShapeData(liveNorm) {
    if (this.tool === "rect") {
      return {
        x: Math.min(this._startX, liveNorm.x),
        y: Math.min(this._startY, liveNorm.y),
        w: Math.abs(liveNorm.x - this._startX),
        h: Math.abs(liveNorm.y - this._startY),
      };
    } else if (this.tool === "ellipse") {
      return {
        cx: (this._startX + liveNorm.x) / 2,
        cy: (this._startY + liveNorm.y) / 2,
        rx: Math.abs(liveNorm.x - this._startX) / 2,
        ry: Math.abs(liveNorm.y - this._startY) / 2,
      };
    } else {
      return { points: this._currentPoints };
    }
  }

  _drawShape(ctx, ann, selected, alpha = 1) {
    const d = ann.shape_data;
    const color = ann.color ?? "#FFC857";
    const W = this.canvas.width;
    const H = this.canvas.height;

    ctx.save();
    ctx.globalAlpha = alpha;
    ctx.strokeStyle = color;
    ctx.lineWidth = selected ? 3 : 2;
    ctx.setLineDash(selected ? [6, 3] : []);
    ctx.fillStyle = color + "33"; // 20% opacity fill

    ctx.beginPath();
    if (ann.shape_type === "rect") {
      ctx.rect(d.x * W, d.y * H, d.w * W, d.h * H);
    } else if (ann.shape_type === "ellipse") {
      ctx.ellipse(d.cx * W, d.cy * H, d.rx * W, d.ry * H, 0, 0, Math.PI * 2);
    } else if (ann.shape_type === "freehand" && d.points?.length) {
      ctx.moveTo(d.points[0][0] * W, d.points[0][1] * H);
      for (let i = 1; i < d.points.length; i++) {
        ctx.lineTo(d.points[i][0] * W, d.points[i][1] * H);
      }
    }
    ctx.fill();
    ctx.stroke();

    // Tag label
    if (ann.tag) {
      const px = ann.shape_type === "rect"
        ? d.x * W
        : ann.shape_type === "ellipse"
        ? (d.cx - d.rx) * W
        : Math.min(...d.points.map((p) => p[0])) * W;
      const py = ann.shape_type === "rect"
        ? d.y * H
        : ann.shape_type === "ellipse"
        ? (d.cy - d.ry) * H
        : Math.min(...d.points.map((p) => p[1])) * H;

      ctx.font = "bold 11px system-ui, sans-serif";
      ctx.fillStyle = color;
      ctx.fillText(ann.tag, px + 4, py - 4);
    }

    ctx.restore();
  }
}

// ── Utility ─────────────────────────────────────────────────────

function _ptSegDist(px, py, ax, ay, bx, by) {
  const dx = bx - ax, dy = by - ay;
  const lenSq = dx * dx + dy * dy;
  if (lenSq === 0) return Math.hypot(px - ax, py - ay);
  const t = Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / lenSq));
  return Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
}
