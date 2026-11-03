CREATE TABLE "crafting_recipes" (
	"code" varchar(50) PRIMARY KEY NOT NULL,
	"name" varchar(100) NOT NULL,
	"target_template_code" varchar(50) NOT NULL,
	"required_forge_level" integer DEFAULT 1 NOT NULL,
	"required_materials" jsonb NOT NULL,
	"craft_fee_silver" integer DEFAULT 0 NOT NULL,
	"is_active" boolean DEFAULT true NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "equipment_instances" ADD COLUMN "star_level" integer DEFAULT 1 NOT NULL;--> statement-breakpoint
ALTER TABLE "equipment_instances" ADD COLUMN "enhance_level" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "equipment_instances" ADD COLUMN "stat_multiplier" double precision DEFAULT 1 NOT NULL;--> statement-breakpoint
ALTER TABLE "equipment_instances" ADD COLUMN "substats" jsonb DEFAULT '{"hp":0,"attack":0,"defense":0,"speed":0}'::jsonb NOT NULL;--> statement-breakpoint
ALTER TABLE "crafting_recipes" ADD CONSTRAINT "crafting_recipes_target_template_code_equipment_templates_code_fk" FOREIGN KEY ("target_template_code") REFERENCES "public"."equipment_templates"("code") ON DELETE no action ON UPDATE no action;