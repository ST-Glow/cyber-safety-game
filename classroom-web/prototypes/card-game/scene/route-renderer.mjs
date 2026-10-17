export function renderRoutes(routes, state) {
  const layer = document.createElement('div');
  layer.className = 'route-layer';
  for (const route of routes) {
    const current = state.routes[route.id];
    const line = document.createElement('span');
    line.className = 'route route-' + route.id + ' route-' + (current?.status || 'open');
    line.title = current?.status === 'congested' ? '拥堵路线' : '可用路线';
    layer.append(line);
  }
  return layer;
}
