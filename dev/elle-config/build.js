// Builds the single-file page: node dev/elle-config/build.js
const fs = require('fs');
const path = require('path');
const src = (f) => fs.readFileSync(path.join(__dirname, 'src', f), 'utf8');
function build() {
  const scripts = ['luatable.js', 'model.js', 'app.js']
    .map((f) => '<script>\n' + src(f).replace(/<\/script/g, '<\\/script') + '\n</script>').join('\n');
  return src('page.html').replace('<!--SCRIPTS-->', () => scripts);
}
module.exports = { build, out: path.join(__dirname, 'elle-config.html') };
if (require.main === module) {
  fs.writeFileSync(module.exports.out, build());
  console.log('wrote elle-config.html');
}
