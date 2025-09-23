import CoffeeScript from "coffeescript";

const files = ['rent', 'work', 'timer', 'shared-utils'];

for (const file of files) {
  const coffee = await Deno.readTextFile(`static/coffee/${file}.coffee`);
  const js = CoffeeScript.compile(coffee, { bare: true });
  await Deno.writeTextFile(`static/js/${file}.js`, js);
  console.log(`Compiled ${file}.coffee to ${file}.js`);
}