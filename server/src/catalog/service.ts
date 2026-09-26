import type postgres from "postgres";
import { wire } from "../db/store";
import { CatalogSchema } from "../domain/records";
import {
  catalogId,
  catalogVersion,
  equipmentNames,
  exerciseData,
  muscleNames,
  slug,
} from "./data";
export async function seedCatalog(client: postgres.Sql) {
  await client.begin(async (sql) => {
    for (const [i, name] of equipmentNames.entries())
      await sql`insert into equipment (id,slug,name) values (${catalogId(1, i)},${slug(name)},${name}) on conflict(id) do nothing`;
    for (const [i, name] of muscleNames.entries())
      await sql`insert into muscle_groups (id,slug,name) values (${catalogId(2, i)},${slug(name)},${name}) on conflict(id) do nothing`;
    for (const [
      i,
      [name, pattern, primary, secondary, gear, unilateral],
    ] of exerciseData.entries()) {
      const id = catalogId(3, i);
      await sql`insert into exercises (id,slug,name,movement_pattern,unilateral,metadata) values (${id},${slug(name)},${name},${pattern},${unilateral},${sql.json({ catalogVersion })}) on conflict(id) do nothing`;
      await sql`insert into exercise_aliases (id,exercise_id,source,alias) values (${catalogId(4, i)},${id},'hybrd',${name}) on conflict do nothing`;
      for (const m of [...primary, ...secondary])
        await sql`insert into exercise_muscles (exercise_id,muscle_group_id,role) values (${id},${catalogId(2, m)},${primary.includes(m) ? "primary" : "secondary"}) on conflict do nothing`;
      for (const e of gear)
        await sql`insert into exercise_equipment (exercise_id,equipment_id,required) values (${id},${catalogId(1, e)},true) on conflict do nothing`;
    }
  });
}
export async function readCatalog(client: postgres.Sql) {
  const [
    exercises,
    equipment,
    muscles,
    aliases,
    exerciseMuscles,
    exerciseEquipment,
  ] = await Promise.all([
    client`select * from exercises order by slug`,
    client`select * from equipment order by slug`,
    client`select * from muscle_groups order by slug`,
    client`select * from exercise_aliases order by alias`,
    client`select * from exercise_muscles order by exercise_id,muscle_group_id`,
    client`select * from exercise_equipment order by exercise_id,equipment_id`,
  ]);
  return CatalogSchema.parse({
    version: catalogVersion,
    exercises: exercises.map(wire),
    equipment: equipment.map(wire),
    muscleGroups: muscles.map(wire),
    aliases: aliases.map(wire),
    exerciseMuscles: exerciseMuscles.map(wire),
    exerciseEquipment: exerciseEquipment.map(wire),
  });
}
