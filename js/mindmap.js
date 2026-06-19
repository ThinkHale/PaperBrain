/**
 * mindmap.js — D3 force-directed mind map for Illuminote
 *
 * Usage:
 *   const map = new MindMap('#mindmap-svg', { onOpenNote, onSavePosition, onSaveRelation });
 *   map.load(notes, relations, positions);
 *   map.resetLayout();
 *   map.filterByTag(tag);
 *   map.destroy();
 *
 * Node types:
 *   - note  → circle, colored by primary tag
 *   - tag   → hexagon, larger
 *
 * Edges:
 *   - AI relation   → solid line, width = score
 *   - manual        → dashed line
 *   - note→tag      → thin dotted (hidden by default, toggle with showTagLinks)
 */

/* global d3 */

const NOTE_R = 28;
const TAG_R  = 36;
const TAG_COLORS = [
  "#FFC857","#5B6472","#E6E8EF","#10b981",
  "#3b82f6","#ef4444","#8b5cf6","#14b8a6",
  "#f97316","#06b6d4","#84cc16","#a855f7",
];

export class MindMap {
  constructor(svgSelector, opts = {}) {
    this.el = document.querySelector(svgSelector);
    this.opts = opts;
    this._showTagLinks = false;
    this._filter = null;
    this._dragSrc = null;
    this._sim = null;
    this._nodes = [];
    this._links = [];
    this._positions = {};
    this._tagColorMap = new Map();
    this._colorIdx = 0;

    this._svg = d3.select(this.el);
    this._g = this._svg.append("g").attr("class", "mm-root");

    // Zoom & pan
    this._zoom = d3.zoom()
      .scaleExtent([0.15, 4])
      .on("zoom", (e) => this._g.attr("transform", e.transform));
    this._svg.call(this._zoom);

    this._svg.on("dblclick.zoom", null); // disable dbl-click zoom default
  }

  _tagColor(tag) {
    if (!this._tagColorMap.has(tag)) {
      this._tagColorMap.set(tag, TAG_COLORS[this._colorIdx % TAG_COLORS.length]);
      this._colorIdx++;
    }
    return this._tagColorMap.get(tag);
  }

  /** Load data and render. */
  load(notes, relations, positions) {
    this._rawNotes = notes;
    this._rawRelations = relations;
    this._positions = {};
    for (const p of positions) {
      this._positions[`${p.node_type}:${p.node_id}`] = { x: p.x, y: p.y };
    }
    this._build();
  }

  _build() {
    const notes = this._rawNotes ?? [];
    const relations = this._rawRelations ?? [];

    // Collect all unique tags
    const tagSet = new Set();
    for (const n of notes) (n.tags ?? []).forEach((t) => tagSet.add(t));

    // Build node list
    this._nodes = [
      ...notes.map((n) => ({
        id: `note:${n.id}`,
        type: "note",
        noteId: n.id,
        label: n.title ?? "Untitled",
        tags: n.tags ?? [],
        color: this._tagColor((n.tags ?? [])[0] ?? "_default"),
        r: NOTE_R,
        fx: this._positions[`note:${n.id}`]?.x ?? null,
        fy: this._positions[`note:${n.id}`]?.y ?? null,
      })),
      ...[...tagSet].map((tag) => ({
        id: `tag:${tag}`,
        type: "tag",
        tag,
        label: `#${tag}`,
        color: this._tagColor(tag),
        r: TAG_R,
        fx: this._positions[`tag:${tag}`]?.x ?? null,
        fy: this._positions[`tag:${tag}`]?.y ?? null,
      })),
    ];

    // Build link list: AI/manual relations
    this._links = relations
      .filter((r) => r.from_id && r.to_id)
      .map((r) => ({
        source: `note:${r.from_id}`,
        target: `note:${r.to_id}`,
        score: r.score ?? 0.5,
        manual: r.manual,
        reason: r.reason ?? "",
        id: r.id,
      }));

    // Note → tag membership links (hidden by default)
    this._tagLinks = [];
    for (const n of notes) {
      for (const tag of (n.tags ?? [])) {
        this._tagLinks.push({
          source: `note:${n.id}`,
          target: `tag:${tag}`,
          isTagLink: true,
        });
      }
    }

    this._render();
  }

  _render() {
    const W = this.el.clientWidth  || 800;
    const H = this.el.clientHeight || 600;

    this._g.selectAll("*").remove();

    const allLinks = this._showTagLinks
      ? [...this._links, ...this._tagLinks]
      : this._links;

    const nodeMap = new Map(this._nodes.map((n) => [n.id, n]));

    // Filter
    const visibleNodes = this._filter
      ? this._nodes.filter(
          (n) =>
            n.type === "tag"
              ? n.tag === this._filter
              : (n.tags ?? []).includes(this._filter),
        )
      : this._nodes;
    const visibleIds = new Set(visibleNodes.map((n) => n.id));
    const visibleLinks = allLinks.filter(
      (l) => visibleIds.has(l.source?.id ?? l.source) && visibleIds.has(l.target?.id ?? l.target),
    );

    // Arrow marker
    this._g.append("defs").append("marker")
      .attr("id", "arrow")
      .attr("viewBox", "0 -5 10 10")
      .attr("refX", 18).attr("refY", 0)
      .attr("markerWidth", 6).attr("markerHeight", 6)
      .attr("orient", "auto")
      .append("path")
      .attr("d", "M0,-5L10,0L0,5")
      .attr("fill", "#94a3b8");

    // Links layer
    const linkG = this._g.append("g").attr("class", "mm-links");
    const linkEl = linkG.selectAll("line")
      .data(visibleLinks)
      .join("line")
      .attr("class", "mm-link")
      .attr("stroke", (d) => d.isTagLink ? "#94a3b855" : d.manual ? "#f59e0b" : "#94a3b8")
      .attr("stroke-width", (d) => d.isTagLink ? 1 : Math.max(1, (d.score ?? 0.5) * 4))
      .attr("stroke-dasharray", (d) => d.manual ? "6 3" : d.isTagLink ? "2 4" : null)
      .attr("marker-end", (d) => d.isTagLink ? null : "url(#arrow)");

    // Tooltip on link hover
    linkEl.append("title").text((d) => d.reason || "");

    // Nodes layer
    const nodeG = this._g.append("g").attr("class", "mm-nodes");
    const nodeEl = nodeG.selectAll("g.mm-node")
      .data(visibleNodes)
      .join("g")
      .attr("class", "mm-node")
      .attr("cursor", "pointer")
      .call(
        d3.drag()
          .on("start", (e, d) => this._onDragStart(e, d))
          .on("drag",  (e, d) => this._onDrag(e, d))
          .on("end",   (e, d) => this._onDragEnd(e, d)),
      )
      .on("click", (e, d) => this._onClick(e, d));

    // Note → circle; Tag → hexagon
    nodeEl.each(function(d) {
      const el = d3.select(this);
      if (d.type === "note") {
        el.append("circle")
          .attr("r", d.r)
          .attr("fill", d.color + "cc")
          .attr("stroke", d.color)
          .attr("stroke-width", 2);
      } else {
        const pts = _hexPoints(d.r);
        el.append("polygon")
          .attr("points", pts)
          .attr("fill", d.color + "99")
          .attr("stroke", d.color)
          .attr("stroke-width", 2.5);
      }
    });

    // Labels
    nodeEl.append("text")
      .attr("text-anchor", "middle")
      .attr("dy", (d) => d.type === "note" ? "0.35em" : "0.35em")
      .attr("font-size", (d) => d.type === "tag" ? 12 : 10)
      .attr("font-weight", (d) => d.type === "tag" ? "bold" : "normal")
      .attr("fill", "#f8fafc")
      .attr("pointer-events", "none")
      .each(function(d) {
        const words = d.label.split(/\s+/);
        const el = d3.select(this);
        if (words.length <= 2 || d.type === "tag") {
          el.text(d.label.length > 18 ? d.label.slice(0, 16) + "…" : d.label);
        } else {
          const line1 = words.slice(0, 2).join(" ");
          const line2 = words.slice(2).join(" ");
          el.append("tspan").attr("x", 0).attr("dy", "-0.6em").text(line1.slice(0, 16));
          el.append("tspan").attr("x", 0).attr("dy", "1.2em").text(line2.slice(0, 16) + (line2.length > 16 ? "…" : ""));
        }
      });

    // Simulation
    this._sim = d3.forceSimulation(visibleNodes)
      .force("link", d3.forceLink(visibleLinks).id((d) => d.id).distance(120).strength(0.4))
      .force("charge", d3.forceManyBody().strength(-300))
      .force("center", d3.forceCenter(W / 2, H / 2))
      .force("collide", d3.forceCollide((d) => d.r + 10))
      .on("tick", () => {
        linkEl
          .attr("x1", (d) => d.source.x)
          .attr("y1", (d) => d.source.y)
          .attr("x2", (d) => d.target.x)
          .attr("y2", (d) => d.target.y);
        nodeEl.attr("transform", (d) => `translate(${d.x},${d.y})`);
      });
  }

  // ── Drag handlers ───────────────────────────────────────────

  _onDragStart(e, d) {
    if (!e.active) this._sim.alphaTarget(0.3).restart();
    d.fx = d.x;
    d.fy = d.y;
  }

  _onDrag(e, d) {
    d.fx = e.x;
    d.fy = e.y;
  }

  _onDragEnd(e, d) {
    if (!e.active) this._sim.alphaTarget(0);
    // Keep pinned
    d.fx = d.x;
    d.fy = d.y;
    // Save position
    const [nodeType, ...rest] = d.id.split(":");
    const nodeId = rest.join(":");
    if (this.opts.onSavePosition) {
      this.opts.onSavePosition({ nodeType, nodeId, x: d.x, y: d.y });
    }
  }

  _onClick(e, d) {
    e.stopPropagation();
    if (e.defaultPrevented) return; // was a drag
    if (d.type === "note" && this.opts.onOpenNote) {
      this.opts.onOpenNote(d.noteId);
    } else if (d.type === "tag") {
      this.filterByTag(d.tag === this._filter ? null : d.tag);
    }
  }

  // ── Public API ──────────────────────────────────────────────

  resetLayout() {
    for (const n of this._nodes) { n.fx = null; n.fy = null; }
    this._render();
  }

  filterByTag(tag) {
    this._filter = tag;
    this._render();
  }

  toggleTagLinks() {
    this._showTagLinks = !this._showTagLinks;
    this._render();
  }

  destroy() {
    if (this._sim) this._sim.stop();
    this._g.selectAll("*").remove();
  }
}

// ── Helpers ─────────────────────────────────────────────────────

function _hexPoints(r) {
  return Array.from({ length: 6 }, (_, i) => {
    const angle = (Math.PI / 3) * i - Math.PI / 6;
    return `${r * Math.cos(angle)},${r * Math.sin(angle)}`;
  }).join(" ");
}
